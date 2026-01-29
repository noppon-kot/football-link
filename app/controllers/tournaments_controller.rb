require "set"

class TournamentsController < ApplicationController
  # ให้ทุกคนเข้า view ได้ทุกเมนูของทัวร์นาเมนต์ ยกเว้น action ที่แก้ไขข้อมูล
  before_action :require_login, except: [:index, :show, :teams, :groups, :fixture, :table, :knockout, :package]
  before_action :set_tournament, only: [:show, :edit, :update, :approve, :teams, :groups, :fixture, :manage_schedule, :table, :knockout, :package, :generate_knockout, :generate_mock_schedule, :assign_slot_teams, :update_points, :update_scores, :bulk_schedule, :destroy, :add_team_to_group, :add_match, :resolve_knockout_slots]
  before_action :require_edit_permission, only: [:edit, :update]
  before_action :require_pro_plan, only: [:groups, :fixture, :table, :knockout, :generate_knockout, :generate_mock_schedule, :assign_slot_teams, :update_points, :update_scores, :update_knockout_teams]
  def index
    result = ::Tournaments::IndexService.new(
      params: params,
      current_user: current_user,
      admin: admin?
    ).call

    @age_categories = result.age_categories
    @provinces      = result.provinces
    @tournaments    = result.tournaments
    @current_page   = result.current_page
    @total_pages    = result.total_pages
  end

  def approve
    result = ::Tournaments::ApproveService.new(
      tournament: @tournament,
      current_user: current_user,
      params: params
    ).call

    if result.success?
      redirect_to mytournaments_path, notice: result.message
    else
      redirect_to mytournaments_path, alert: result.message
    end
  end

  def update_knockout_teams
    unless can_manage_registrations?(@tournament)
      return redirect_to knockout_tournament_path(@tournament), alert: I18n.t("sessions.flash.login_required")
    end

    matches_params = params[:matches] || {}

    Match.transaction do
      matches_params.each do |match_id, attrs|
        match = Match.find_by(id: match_id)
        next unless match&.knockout?

        permitted = attrs.permit(:home_team_id, :away_team_id)

        update_attrs = {}
        update_attrs[:home_team_id] = permitted[:home_team_id].presence
        update_attrs[:away_team_id] = permitted[:away_team_id].presence

        match.update!(update_attrs)
      end
    end

    redirect_to knockout_tournament_path(@tournament), notice: "บันทึกการเลือกทีมในรอบน็อคเอาท์เรียบร้อยแล้ว"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to knockout_tournament_path(@tournament), alert: e.record.errors.full_messages.join(", ")
  end

  def show
    # @tournament is loaded in before_action :set_tournament
  end

  def teams
    # ใช้ @tournament จาก set_tournament และ logic เดิมใน view สำหรับทีมที่สนใจ / สมัคร
  end

  def package
    # หน้าแสดงแพ็กเกจ/สิทธิ์การใช้งานของรายการนี้
  end

  def manage_schedule
    unless can_manage_registrations?(@tournament)
      return redirect_to fixture_tournament_path(@tournament), alert: I18n.t("sessions.flash.login_required")
    end

    divisions = @tournament.tournament_divisions.order(:position, :id)
    @all_matches = Match.where(tournament_division_id: divisions.pluck(:id))
                        .includes(:home_team, :away_team, :group, :tournament_division)
                        .order(:kickoff_at, :id)
    @divisions = divisions
    @selected_day = if params[:day].present?
                      begin
                        Date.parse(params[:day].to_s)
                      rescue ArgumentError
                        Time.zone.today
                      end
                    else
                      Time.zone.today
                    end
  end

  def groups
    # ใช้ @tournament จาก set_tournament และ logic แบ่งสาย/จัดทีมลงสายใน view ใหม่
  end

  def fixture
    divisions = @tournament.tournament_divisions.select(:id)
    today_start = Time.zone.today.beginning_of_day

    @available_pitches = Match.where(tournament_division_id: divisions)
                              .where.not(kickoff_at: nil)
                              .distinct
                              .order(:pitch_no)
                              .pluck(:pitch_no)
                              .map { |p| p.to_i }
                              .select { |p| p >= 1 && p <= 6 }

    @selected_pitch = params[:pitch].to_i
    @selected_pitch = 1 if @selected_pitch <= 0
    @selected_pitch = 6 if @selected_pitch > 6

    if @available_pitches.any?
      @selected_pitch = @available_pitches.include?(@selected_pitch) ? @selected_pitch : @available_pitches.first
    end

    show_mine = params[:mine].to_s == "1" && current_user.present?
    managed_team_ids = []
    if show_mine
      managed_entry_ids_from_manager_user = TeamRegistration.where(tournament_id: @tournament.id, manager_user_id: current_user.id).pluck(:id)
      managed_entry_ids_from_join = TeamRegistrationManager.where(user_id: current_user.id).joins(:team_registration).where(team_registrations: { tournament_id: @tournament.id }).pluck(:team_registration_id)
      managed_entry_ids = (managed_entry_ids_from_manager_user + managed_entry_ids_from_join).uniq
      managed_team_ids = TeamRegistration.where(id: managed_entry_ids).pluck(:team_id).compact.uniq
      show_mine = false if managed_team_ids.empty?
    end

    requested_day = nil
    if params[:day].present?
      begin
        requested_day = Date.parse(params[:day].to_s)
      rescue ArgumentError
        requested_day = nil
      end
    end

    all_dated = Match.where(tournament_division_id: divisions)
                     .where(pitch_no: @selected_pitch)
                     .where.not(kickoff_at: nil)
    if show_mine
      all_dated = all_dated.where("home_team_id IN (:ids) OR away_team_id IN (:ids)", ids: managed_team_ids)
    end

    available_days = all_dated
                      .distinct
                      .order(Arel.sql("DATE(matches.kickoff_at) ASC"))
                      .pluck(Arel.sql("DATE(matches.kickoff_at)"))
                      .map { |d| d.is_a?(Date) ? d : d.to_date }

    @available_days = available_days

    upcoming = all_dated
                .where("kickoff_at >= ?", today_start)
                .order(:kickoff_at, :id)

    @next_match = upcoming.includes(:home_team, :away_team, :group).first

    resolved_day = nil
    if requested_day.present?
      if available_days.include?(requested_day)
        resolved_day = requested_day
      else
        resolved_day = available_days.find { |d| d >= requested_day } || available_days.reverse.find { |d| d <= requested_day }
      end
    else
      today = Time.zone.today
      resolved_day = available_days.find { |d| d >= today } || available_days.last
    end

    @selected_day = resolved_day
    @next_match_day = resolved_day

    if resolved_day.present?
      idx = available_days.index(resolved_day)
      @prev_match_day = idx && idx > 0 ? available_days[idx - 1] : nil
      @next_match_day_nav = idx && idx < (available_days.length - 1) ? available_days[idx + 1] : nil
    else
      @prev_match_day = nil
      @next_match_day_nav = nil
    end

    @next_day_matches = if resolved_day.present?
                          base = Match.where(tournament_division_id: divisions)
                                     .where(pitch_no: @selected_pitch)
                                     .where(kickoff_at: resolved_day.beginning_of_day..resolved_day.end_of_day)
                          if show_mine
                            base = base.where("home_team_id IN (:ids) OR away_team_id IN (:ids)", ids: managed_team_ids)
                          end
                          base.includes(:home_team, :away_team, :group, :tournament_division)
                              .order(:kickoff_at, :id)
                        else
                          Match.none
                        end

    # แสดงทุกคู่ (ไม่ paginate ในหน้าหลัก)
    @next_day_matches_total = @next_day_matches.count
    @next_day_matches_page = @next_day_matches.to_a
    @day_per_page = @next_day_matches_total
    @day_page = 1
    @next_day_matches_total_pages = 1

    all_matches_base = Match.where(tournament_division_id: divisions)
    if show_mine
      all_matches_base = all_matches_base.where("home_team_id IN (:ids) OR away_team_id IN (:ids)", ids: managed_team_ids)
    end
    all_matches_base = all_matches_base.includes(:home_team, :away_team, :group, :tournament_division)

    # คู่ที่ยังไม่แข่ง (ไม่มีสกอร์ครบ) ให้ขึ้นก่อน แล้วค่อยเรียงตามวันเวลา
    all_matches_base = all_matches_base.order(
      Arel.sql("CASE WHEN matches.home_score IS NOT NULL AND matches.away_score IS NOT NULL THEN 1 ELSE 0 END ASC"),
      Arel.sql("CASE WHEN matches.kickoff_at IS NULL THEN 1 ELSE 0 END ASC"),
      Arel.sql("matches.kickoff_at ASC"),
      :id
    )

    @all_per_page = 30
    @all_page = params[:all_page].to_i
    @all_page = 1 if @all_page <= 0
    @all_matches_total = all_matches_base.count
    @all_matches_total_pages = (@all_matches_total.to_f / @all_per_page).ceil
    all_offset = (@all_page - 1) * @all_per_page
    @all_matches_page = all_matches_base.offset(all_offset).limit(@all_per_page)

    @all_matches_for_all_match = Match.where(tournament_division_id: divisions)
                                  .left_joins(:group)
                                  .includes(:group, :home_team, :away_team, :tournament_division)
                                  .order(Arel.sql("matches.stage ASC, groups.name ASC NULLS LAST, matches.round_number ASC NULLS LAST, matches.position ASC NULLS LAST, matches.id ASC"))

    match_ids_for_lineup = (@next_day_matches_page.map(&:id) + @all_matches_page.map(&:id)).uniq
    @lineup_submitted_by_match_and_side = {}
    if match_ids_for_lineup.any?
      MatchLineup.where(match_id: match_ids_for_lineup)
                .pluck(:match_id, :side, :submitted_at)
                .each do |match_id, side, submitted_at|
        @lineup_submitted_by_match_and_side[[match_id, side.to_s]] = submitted_at.present?
      end
    end

    matches_for_roster = (@next_day_matches_page + @all_matches_page).uniq { |m| m.id }
    @roster_submitted_by_match_and_side = {}
    @entry_id_by_match_and_side = {}
    @manageable_entry_ids = Set.new
    if matches_for_roster.any?
      division_ids_for_roster = matches_for_roster.map(&:tournament_division_id).compact.uniq
      team_ids_for_roster = matches_for_roster.flat_map { |m| [m.home_team_id, m.away_team_id] }.compact.uniq

      entries_by_div_and_team = {}
      if division_ids_for_roster.any? && team_ids_for_roster.any?
        TeamRegistration
          .where(tournament_id: @tournament.id)
          .where(tournament_division_id: division_ids_for_roster)
          .where(team_id: team_ids_for_roster)
          .select(:id, :team_id, :tournament_division_id, :roster_locked)
          .find_each do |tr|
            entries_by_div_and_team[[tr.tournament_division_id, tr.team_id]] = tr
          end
      end

      matches_for_roster.each do |m|
        home_entry = if m.home_team_id.present?
                       entries_by_div_and_team[[m.tournament_division_id, m.home_team_id]]
                     end
        away_entry = if m.away_team_id.present?
                       entries_by_div_and_team[[m.tournament_division_id, m.away_team_id]]
                     end

        @roster_submitted_by_match_and_side[[m.id, "home"]] = !!home_entry&.roster_locked?
        @roster_submitted_by_match_and_side[[m.id, "away"]] = !!away_entry&.roster_locked?

        @entry_id_by_match_and_side[[m.id, "home"]] = home_entry&.id
        @entry_id_by_match_and_side[[m.id, "away"]] = away_entry&.id
      end
    end

    if current_user.present?
      ids_from_manager_user = TeamRegistration.where(tournament_id: @tournament.id, manager_user_id: current_user.id).pluck(:id)
      ids_from_join = TeamRegistrationManager.where(user_id: current_user.id).joins(:team_registration).where(team_registrations: { tournament_id: @tournament.id }).pluck(:team_registration_id)
      @manageable_entry_ids = (ids_from_manager_user + ids_from_join).uniq.to_set
    end
  end

  def bulk_schedule
    unless can_manage_registrations?(@tournament)
      return redirect_to fixture_tournament_path(@tournament), alert: I18n.t("sessions.flash.login_required")
    end

    divisions = @tournament.tournament_divisions.select(:id)
    first_schedule_date = nil
    total_matches_updated = 0

    if params[:batches].present?
      Match.transaction do
        params[:batches].each do |_batch_idx, batch_params|
          batch_match_ids = Array(batch_params[:match_ids]).map(&:to_i).uniq
          next if batch_match_ids.empty?

          minutes_per_half = batch_params[:minutes_per_half].to_i
          halves_count = batch_params[:halves_count].to_i
          break_between_halves_min = batch_params[:break_between_halves].to_i
          break_between_matches_min = batch_params[:break_between_matches].to_i
          pitch_no = batch_params[:pitch_no].to_i
          date_str = batch_params[:schedule_date].to_s.strip
          start_time_str = batch_params[:start_time].to_s.strip

          minutes_per_half = 10 if minutes_per_half <= 0
          halves_count = 2 if halves_count <= 0
          break_between_halves_min = 0 if break_between_halves_min < 0
          break_between_matches_min = 0 if break_between_matches_min < 0
          pitch_no = 1 if pitch_no <= 0
          pitch_no = 6 if pitch_no > 6

          begin
            schedule_date = Date.parse(date_str)
          rescue ArgumentError
            next
          end

          first_schedule_date ||= schedule_date

          begin
            start_at = Time.zone.parse("#{schedule_date} #{start_time_str}")
          rescue ArgumentError, TypeError
            next
          end

          next if start_at.blank?

          matches_by_id = Match.where(tournament_division_id: divisions, id: batch_match_ids).index_by(&:id)
          ordered_matches = batch_match_ids.filter_map { |id| matches_by_id[id] }
          next if ordered_matches.empty?

          match_minutes = (minutes_per_half * halves_count) + (halves_count > 1 ? ((halves_count - 1) * break_between_halves_min) : 0)
          match_minutes = 1 if match_minutes <= 0

          current_kickoff = start_at
          ordered_matches.each do |m|
            m.update!(kickoff_at: current_kickoff, pitch_no: pitch_no)
            current_kickoff = current_kickoff + match_minutes.minutes + break_between_matches_min.minutes
            total_matches_updated += 1
          end
        end
      end

      if total_matches_updated > 0
        redirect_to fixture_tournament_path(@tournament, day: first_schedule_date&.strftime("%Y-%m-%d")), notice: "ตั้งเวลาแข่งเรียบร้อยแล้ว #{total_matches_updated} คู่"
      else
        redirect_to fixture_tournament_path(@tournament), alert: "ไม่พบคู่ที่เลือก"
      end
    else
      match_ids = Array(params[:match_ids]).map(&:to_i).uniq
      if match_ids.empty?
        return redirect_to fixture_tournament_path(@tournament), alert: "กรุณาเลือกคู่ที่ต้องการตั้งเวลา"
      end

      minutes_per_half = params[:minutes_per_half].to_i
      halves_count = params[:halves_count].to_i
      break_between_halves_min = params[:break_between_halves].to_i
      break_between_matches_min = params[:break_between_matches].to_i
      pitch_no = params[:pitch_no].to_i
      date_str = params[:schedule_date].to_s.strip
      start_time_str = params[:start_time].to_s.strip

      minutes_per_half = 10 if minutes_per_half <= 0
      halves_count = 2 if halves_count <= 0
      break_between_halves_min = 0 if break_between_halves_min < 0
      break_between_matches_min = 0 if break_between_matches_min < 0
      pitch_no = 1 if pitch_no <= 0
      pitch_no = 6 if pitch_no > 6

      begin
        schedule_date = Date.parse(date_str)
      rescue ArgumentError
        schedule_date = nil
      end

      if schedule_date.blank? || start_time_str.blank?
        return redirect_to fixture_tournament_path(@tournament), alert: "กรุณาเลือกวันที่ และเวลาเริ่มแข่ง"
      end

      begin
        start_at = Time.zone.parse("#{schedule_date} #{start_time_str}")
      rescue ArgumentError, TypeError
        start_at = nil
      end

      if start_at.blank?
        return redirect_to fixture_tournament_path(@tournament), alert: "เวลาเริ่มแข่งไม่ถูกต้อง"
      end

      matches_by_id = Match.where(tournament_division_id: divisions, id: match_ids).index_by(&:id)
      ordered_matches = match_ids.filter_map { |id| matches_by_id[id] }

      if ordered_matches.empty?
        return redirect_to fixture_tournament_path(@tournament), alert: "ไม่พบคู่ที่เลือก"
      end

      match_minutes = (minutes_per_half * halves_count) + (halves_count > 1 ? ((halves_count - 1) * break_between_halves_min) : 0)
      match_minutes = 1 if match_minutes <= 0

      current_kickoff = start_at
      Match.transaction do
        ordered_matches.each do |m|
          m.update!(kickoff_at: current_kickoff, pitch_no: pitch_no)
          current_kickoff = current_kickoff + match_minutes.minutes + break_between_matches_min.minutes
        end
      end

      redirect_to fixture_tournament_path(@tournament, day: schedule_date.strftime("%Y-%m-%d")), notice: "ตั้งเวลาแข่งเรียบร้อยแล้ว"
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_to fixture_tournament_path(@tournament), alert: e.record.errors.full_messages.join(", ")
  end

  def table
    counts = MatchEvent
             .joins(:tournament_player, match: :tournament_division)
             .where(event_type: :goal)
             .where(tournament_divisions: { tournament_id: @tournament.id })
             .group("tournament_divisions.id", "match_events.tournament_player_id")
             .count

    player_ids = counts.keys.map { |(_div_id, pid)| pid }.uniq
    players_by_id = TournamentPlayer
                    .includes(team_registration: :team)
                    .where(id: player_ids)
                    .index_by(&:id)

    grouped = Hash.new { |h, k| h[k] = [] }
    counts.each do |(div_id, pid), goals|
      player = players_by_id[pid]
      next unless player
      grouped[div_id] << [player, goals]
    end

    @top_scorers_by_division = {}
    grouped.each do |div_id, arr|
      @top_scorers_by_division[div_id] = arr.sort_by { |(_p, g)| -g }.first(3)
    end
  end

  def knockout
    # รอบน็อคเอาท์ของแต่ละรุ่น: จะใช้แมตช์ที่ stage = :knockout
  end

  def generate_knockout
    unless can_manage_registrations?(@tournament)
      return redirect_to knockout_tournament_path(@tournament), alert: I18n.t("sessions.flash.login_required")
    end

    division = @tournament.tournament_divisions.find(params[:division_id])

    result = ::Tournaments::GenerateKnockoutBracketService.new(
      division: division,
      bracket_size: params[:bracket_size],
      include_third_place: params[:include_third_place]
    ).call

    if result.success?
      redirect_to knockout_tournament_path(@tournament), notice: result.message
    else
      redirect_to knockout_tournament_path(@tournament), alert: result.message
    end
  end

  def generate_mock_schedule
    unless can_manage_registrations?(@tournament)
      return redirect_to groups_tournament_path(@tournament), alert: I18n.t("sessions.flash.login_required")
    end

    division_id_for_mode = params[:division_id].to_s
    competition_mode = params.dig(:competition_mode, division_id_for_mode).presence || "group_with_knockout"
    target_path = groups_tournament_path(@tournament)

    division = @tournament.tournament_divisions.find_by(id: params[:division_id])
    unless division
      return redirect_to target_path, alert: "ไม่พบรุ่นการแข่งขันที่เลือก"
    end

    if competition_mode == "knockout_only"
      # โหมดน็อคเอาท์อย่างเดียว: ไม่สร้างรอบแบ่งกลุ่ม สร้างเฉพาะรอบน็อคเอาท์จากจำนวนทีมที่มีอยู่
      total_teams = division.team_registrations.confirmed_for_competition.distinct.count(:team_id)
      if total_teams.zero?
        return redirect_to target_path, alert: "รุ่นนี้ยังไม่มีทีม ไม่สามารถสร้างรอบน็อคเอาท์ได้"
      end

      # ล้างข้อมูลรอบแบ่งกลุ่มเดิมทิ้งทั้งหมดของรุ่นนี้ (ถ้ามี) แล้วสร้างสาย A/B ใหม่
      division.matches.group_stage.destroy_all
      # ล้าง group_id ใน team_registrations ก่อนลบ groups (เพื่อป้องกัน foreign key violation)
      division.team_registrations.update_all(group_id: nil)
      division.groups.destroy_all

      group_a = division.groups.create!(name: "A")
      group_b = division.groups.create!(name: "B")

      # ปัดจำนวนทีมขึ้นเป็นเลขคู่ขั้นต่ำ แล้วปัดขึ้นเป็น 4/8/16/32/64 ใกล้สุด (ไม่เกิน 64)
      adjusted = [total_teams, 2].max
      adjusted += 1 if adjusted.odd?

      possible_sizes = [4, 8, 16, 32, 64]
      bracket_size = possible_sizes.find { |s| s >= adjusted } || 64

      include_third_place = ActiveModel::Type::Boolean.new.cast(params[:include_third_place])

      ko_result = ::Tournaments::GenerateKnockoutBracketService.new(
        division: division,
        bracket_size: bracket_size,
        include_third_place: include_third_place,
        enforce_max_by_team_count: false,
        knockout_only: true
      ).call

      if ko_result.success?
        redirect_to target_path, notice: "สร้างรอบน็อคเอาท์จำนวน #{bracket_size} ทีมเรียบร้อยแล้ว"
      else
        redirect_to target_path, alert: ko_result.message
      end
    elsif competition_mode == "league_only"
      # ระบบลีก: มีแค่รอบแบ่งกลุ่ม ไม่มีน็อคเอาท์
      result = ::Tournaments::GenerateMockScheduleHandler.new(
        tournament: @tournament,
        params: params,
        can_manage: can_manage_registrations?(@tournament)
      ).call

      if result.success?
        redirect_to target_path, notice: result.message
      else
        redirect_to target_path, alert: result.message
      end
    else
      # ระบบแบ่งกลุ่ม (ต้องมีรอบน็อคเอาท์เสมอ)
      if params[:knockout_bracket_size].blank?
        return redirect_to target_path, alert: "กรุณาเลือกจำนวนทีมที่เข้ารอบน็อคเอาท์"
      end

      # ตรวจจำนวนสายไม่ให้เกินจำนวนทีม (อย่างน้อย 2 ทีมต่อสาย)
      total_teams = division.team_registrations.confirmed_for_competition.distinct.count(:team_id)
      group_count = params[:group_count].to_i
      if total_teams > 0 && group_count > 0
        max_groups = [1, total_teams / 2].max
        if group_count > max_groups
          return redirect_to target_path, alert: "รุ่นนี้มีทีมทั้งหมด #{total_teams} ทีม แบ่งได้ไม่เกิน #{max_groups} สาย (อย่างน้อย 2 ทีมต่อสาย)"
        end
      end

      result = ::Tournaments::GenerateMockScheduleHandler.new(
        tournament: @tournament,
        params: params,
        can_manage: can_manage_registrations?(@tournament)
      ).call

      if result.success?
        knockout_message = nil

        begin
          bracket_size = params[:knockout_bracket_size].to_i
          include_third_place = ActiveModel::Type::Boolean.new.cast(params[:include_third_place])

          ko_result = ::Tournaments::GenerateKnockoutBracketService.new(
            division: division,
            bracket_size: bracket_size,
            include_third_place: include_third_place
          ).call

          if ko_result.success?
            knockout_message = " และสร้างรอบน็อคเอาท์จำนวน #{bracket_size} ทีมแล้ว"
          else
            knockout_message = " (แต่ไม่สามารถสร้างรอบน็อคเอาท์ได้: #{ko_result.message})"
          end
        rescue StandardError => e
          knockout_message = " (มีข้อผิดพลาดระหว่างสร้างรอบน็อคเอาท์: #{e.message})"
        end

        full_message = [result.message, knockout_message].compact.join
        redirect_to target_path, notice: full_message
      else
        redirect_to target_path, alert: result.message
      end
    end
  end

  def assign_slot_teams
    unless can_manage_registrations?(@tournament)
      return redirect_to groups_tournament_path(@tournament), alert: I18n.t("sessions.flash.login_required")
    end

    division = @tournament.tournament_divisions.find(params[:division_id])

    result = ::Tournaments::AssignTeamsToSlotsService.new(
      division: division,
      slot_assignments: params[:slot_assignments]
    ).call

    if result.success?
      redirect_to groups_tournament_path(@tournament), notice: "บันทึกการจัดทีมลงสายเรียบร้อยแล้ว"
    else
      redirect_to groups_tournament_path(@tournament), alert: result.errors.join(", ")
    end
  end

  def update_points
    unless can_manage_registrations?(@tournament)
      return redirect_to table_tournament_path(@tournament), alert: I18n.t("sessions.flash.login_required")
    end

    attrs = params.require(:division).permit(:points_win, :points_draw, :points_loss, :draw_mode, :points_pk_win, :points_pk_loss)

    divisions = @tournament.tournament_divisions
    errors = []

    ActiveRecord::Base.transaction do
      divisions.each do |division|
        unless division.update(attrs)
          errors = division.errors.full_messages
          raise ActiveRecord::Rollback
        end
      end
    end

    if errors.empty?
      redirect_to table_tournament_path(@tournament), notice: "อัปเดตกติกาคะแนนเรียบร้อยแล้ว (ใช้กับทุกรุ่น)"
    else
      redirect_to table_tournament_path(@tournament), alert: errors.join(", ")
    end
  end

  def update_scores
    unless can_manage_registrations?(@tournament)
      return redirect_to fixture_tournament_path(@tournament), alert: I18n.t("sessions.flash.login_required")
    end

    # รีเซ็ตสกอร์ของแมตช์เดียว (ใช้จากปุ่ม Reset score ในหน้าโปรแกรม/ผล)
    if params[:reset_match_id].present?
      match = Match.find_by(id: params[:reset_match_id])
      if match && match.tournament_division.tournament_id == @tournament.id
        match.update!(
          home_score: nil,
          away_score: nil,
          decided_by_penalty: false,
          penalty_winner_side: nil
        )
        return redirect_to fixture_tournament_path(@tournament), notice: "รีเซ็ตสกอร์ของแมตช์เรียบร้อยแล้ว"
      end

      return redirect_to fixture_tournament_path(@tournament), alert: "ไม่พบแมตช์ที่ต้องการรีเซ็ตสกอร์"
    end

    matches_params = params[:matches] || {}
    affected_division_ids = Set.new
    last_kickoff_day = nil

    Match.transaction do
      matches_params.each do |match_id, attrs|
        match = Match.find_by(id: match_id)
        next unless match

        permitted = attrs.permit(:home_score, :away_score, :kickoff_at, :penalty_winner_side, :home_team_id, :away_team_id, :pitch_no)

        update_attrs = {}

        # เลือกทีมลงคู่ (อนุญาตให้ผู้จัดกำหนดเอง)
        if permitted[:home_team_id].present?
          update_attrs[:home_team_id] = permitted[:home_team_id]
        end
        if permitted[:away_team_id].present?
          update_attrs[:away_team_id] = permitted[:away_team_id]
        end

        # วันเวลาแข่ง
        # NOTE: kickoff_at อาจถูกส่งมาเป็น "" เพื่อเคลียร์วันเวลา
        unless permitted[:kickoff_at].nil?
          submitted_kickoff_at = permitted[:kickoff_at].to_s
          current_kickoff_at = match.kickoff_at&.strftime("%Y-%m-%dT%H:%M")

          if submitted_kickoff_at.blank?
            if match.kickoff_at.present?
              update_attrs[:kickoff_at] = nil
            end
          elsif current_kickoff_at != submitted_kickoff_at
            parsed_time = nil
            begin
              parsed_time = Time.zone.parse(submitted_kickoff_at)
            rescue ArgumentError, TypeError
              parsed_time = nil
            end

            update_attrs[:kickoff_at] = parsed_time || submitted_kickoff_at
            last_kickoff_day = (parsed_time&.to_date || (Date.parse(submitted_kickoff_at) rescue nil) || last_kickoff_day)
          end
        end

        # สกอร์: ต้องกรอกทั้งสองฝั่งถึงจะบันทึก และต้องเปลี่ยนจริงเท่านั้นถึงจะนับว่าเปลี่ยน
        home_score = permitted[:home_score]
        away_score = permitted[:away_score]
        scores_changed = false

        if home_score.present? || away_score.present?
          next if home_score.blank? || away_score.blank?

          if match.home_score.to_s != home_score.to_s || match.away_score.to_s != away_score.to_s
            update_attrs[:home_score] = home_score
            update_attrs[:away_score] = away_score
            scores_changed = true
          end
        end

        # สนาม (pitch_no)
        unless permitted[:pitch_no].nil?
          pitch_no_val = permitted[:pitch_no].to_s.strip
          if pitch_no_val.blank?
            update_attrs[:pitch_no] = nil if match.pitch_no.present?
          elsif match.pitch_no.to_s != pitch_no_val
            update_attrs[:pitch_no] = pitch_no_val.to_i
          end
        end

        # จุดโทษ: เชื่อค่าจาก dropdown โดยตรง
        winner_side_param = permitted[:penalty_winner_side]
        unless winner_side_param.nil?
          winner_side = winner_side_param.presence
          update_attrs[:decided_by_penalty]    = winner_side.present?
          update_attrs[:penalty_winner_side]   = winner_side
        end

        if update_attrs.any?
          match.update!(update_attrs)
          affected_division_ids << match.tournament_division_id

        end
      end
    end

    division_ids = affected_division_ids.to_a
    auto_seed_message = auto_seed_knockout_if_ready(division_ids)
    advance_message = auto_advance_knockout_winners(division_ids)

    notice_msg = ["บันทึกข้อมูลเรียบร้อยแล้ว", auto_seed_message, advance_message].compact.join(" ")
    redirect_params = {}
    redirect_params[:day] = (last_kickoff_day || (params[:day].presence && Date.parse(params[:day])) rescue nil)&.strftime("%Y-%m-%d")
    redirect_params[:page] = params[:page] if params[:page].present?

    # ถ้ามาจากหน้า manage_schedule ให้กลับไปหน้านั้น
    if params[:from_manage_schedule].present?
      redirect_to manage_schedule_tournament_path(@tournament), notice: notice_msg
    else
      redirect_to fixture_tournament_path(@tournament, redirect_params), notice: notice_msg
    end
  rescue ActiveRecord::RecordInvalid => e
    if params[:from_manage_schedule].present?
      redirect_to manage_schedule_tournament_path(@tournament), alert: e.record.errors.full_messages.join(", ")
    else
      redirect_to fixture_tournament_path(@tournament), alert: e.record.errors.full_messages.join(", ")
    end
  end

  def new
    @tournament = Tournament.new
    if current_user
      @tournament.contact_phone ||= current_user.phone
      @tournament.line_id       ||= current_user.line_id
    end

    @tournament.tournament_divisions.build if @tournament.tournament_divisions.empty?
  end

  def edit
    # เติมช่องว่างสำหรับเพิ่มรุ่น (ไม่ใช้ JS) ให้แก้ไขภายหลังได้
    max_divisions = 5
    existing = @tournament.tournament_divisions.size
    to_build = [max_divisions - existing, 0].max
    to_build.times { @tournament.tournament_divisions.build }
  end

  def create
    attrs = tournament_params.dup
    # ถ้าไม่ได้ระบุ organizer มาจากฟอร์ม ให้ผูกกับผู้ใช้ปัจจุบัน
    attrs[:organizer_id] ||= current_user&.id

    service = ::Tournaments::CreateService.new(attrs)
    @tournament = service.tournament

    if service.call
      if current_user
        update_attrs = {}
        update_attrs[:phone]   = @tournament.contact_phone if @tournament.contact_phone.present?
        update_attrs[:line_id] = @tournament.line_id       if @tournament.line_id.present?
        current_user.update(update_attrs) if update_attrs.any?
      end
      redirect_to tournament_path(@tournament), notice: "#{I18n.t('tournaments.flash.create_success')} รหัสรายการ: #{@tournament.id}"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @tournament = Tournament.find(params[:id])
    permitted = tournament_params.to_h

    ok = false

    # ถ้าไม่ได้เลือกไฟล์รูปใหม่ อย่าไปแตะ images เดิม
    if permitted.key?("images")
      images_val = permitted["images"]
      if images_val.blank? || (images_val.is_a?(Array) && images_val.all?(&:blank?))
        permitted.delete("images")
      end
    end

    ActiveRecord::Base.transaction do
      # มีการอัปโหลดรูปใหม่: แทนที่รูปเดิม (ระบบจำกัด 1 รูป)
      if permitted.key?("images")
        @tournament.images_attachments.destroy_all if @tournament.images.attached?
      end

      service = ::Tournaments::UpdateService.new(@tournament, permitted)
      ok = service.call

      raise ActiveRecord::Rollback unless ok
    end

    if ok
      redirect_to @tournament, notice: I18n.t("tournaments.flash.update_success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    unless admin?
      return redirect_to @tournament, alert: I18n.t("sessions.flash.login_required")
    end

    @tournament.destroy
    redirect_to tournaments_path, notice: "ลบรายการแข่งขันเรียบร้อยแล้ว"
  end

  def add_team_to_group
    unless can_manage_registrations?(@tournament)
      return redirect_to groups_tournament_path(@tournament), alert: I18n.t("sessions.flash.login_required")
    end

    team_registration = @tournament.team_registrations.find(params[:team_registration_id])
    group = Group.find(params[:group_id])

    # Verify group belongs to same division as team registration
    unless team_registration.tournament_division_id == group.tournament_division_id
      return redirect_to groups_tournament_path(@tournament), alert: "ทีมและสายไม่อยู่ในรุ่นเดียวกัน"
    end

    division = group.tournament_division
    new_team = team_registration.team
    
    # Find next available slot label for this group
    existing_slots = division.matches.where(group: group)
                            .pluck(:home_slot_label, :away_slot_label)
                            .flatten.compact.uniq
    
    # Extract numbers from existing slots (e.g., "A1" -> 1, "B2" -> 2)
    existing_numbers = existing_slots.map { |s| s.to_s.scan(/\d+/).first.to_i }.compact
    next_number = (existing_numbers.max || 0) + 1
    new_slot_label = "#{group.name}#{next_number}"

    # Get existing teams in this group from matches
    existing_team_ids = division.matches.group_stage.where(group: group)
                               .pluck(:home_team_id, :away_team_id)
                               .flatten.compact.uniq

    Match.transaction do
      # Update team registration with group
      team_registration.update!(group_id: group.id)

      # Create matches against all existing teams in the group
      existing_team_ids.each do |opponent_id|
        opponent = Team.find_by(id: opponent_id)
        next unless opponent

        # Find opponent's slot label
        opponent_slot = existing_slots.find do |slot|
          match = division.matches.group_stage.where(group: group)
                         .where("home_team_id = ? OR away_team_id = ?", opponent_id, opponent_id)
                         .first
          next unless match
          (match.home_team_id == opponent_id && match.home_slot_label == slot) ||
          (match.away_team_id == opponent_id && match.away_slot_label == slot)
        end

        # Create match: new team vs opponent
        Match.create!(
          tournament_division: division,
          group: group,
          stage: :group_stage,
          home_team_id: new_team.id,
          away_team_id: opponent_id,
          home_slot_label: new_slot_label,
          away_slot_label: opponent_slot
        )
      end
    end

    matches_created = existing_team_ids.size
    redirect_to groups_tournament_path(@tournament), notice: "เพิ่มทีม #{new_team.name} เข้าสาย #{group.name} เรียบร้อยแล้ว (Slot: #{new_slot_label}, สร้าง #{matches_created} คู่แข่งขัน)"
  rescue ActiveRecord::RecordNotFound
    redirect_to groups_tournament_path(@tournament), alert: "ไม่พบทีมหรือสายที่ระบุ"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to groups_tournament_path(@tournament), alert: e.record.errors.full_messages.join(", ")
  end

  def add_match
    unless can_manage_registrations?(@tournament)
      return redirect_to manage_schedule_tournament_path(@tournament), alert: I18n.t("sessions.flash.login_required")
    end

    division = @tournament.tournament_divisions.find(params[:division_id])
    
    # Parse kickoff datetime from date and time fields
    kickoff_at = nil
    if params[:kickoff_date].present? && params[:kickoff_time].present?
      kickoff_at = Time.zone.parse("#{params[:kickoff_date]} #{params[:kickoff_time]}")
    elsif params[:kickoff_date].present?
      kickoff_at = Time.zone.parse("#{params[:kickoff_date]} 00:00")
    end

    match_attrs = {
      tournament_division: division,
      stage: params[:stage] || :group_stage,
      home_team_id: params[:home_team_id].presence,
      away_team_id: params[:away_team_id].presence,
      home_slot_label: params[:home_slot_label].presence,
      away_slot_label: params[:away_slot_label].presence,
      kickoff_at: kickoff_at,
      pitch_no: params[:pitch_no].presence
    }

    # Set group if group stage
    if params[:group_id].present?
      match_attrs[:group_id] = params[:group_id]
    end

    # Set round info if knockout
    if params[:stage] == "knockout"
      match_attrs[:round_label] = params[:round_label].presence
      match_attrs[:round_number] = params[:round_number].presence
    end

    Match.transaction do
      # Auto-shift existing matches if requested
      if params[:auto_shift_time] == "1" && kickoff_at.present?
        match_duration = (params[:match_duration].presence || 30).to_i.minutes
        
        # Get all tournament matches at or after the new match time
        division_ids = @tournament.tournament_divisions.pluck(:id)
        matches_to_shift = Match.where(tournament_division_id: division_ids)
                                .where("kickoff_at >= ?", kickoff_at)
                                .order(:kickoff_at)
        
        # Shift each match by match_duration
        matches_to_shift.each do |m|
          m.update!(kickoff_at: m.kickoff_at + match_duration)
        end
      end

      Match.create!(match_attrs)
    end

    redirect_path = params[:return_to].presence || manage_schedule_tournament_path(@tournament)
    redirect_to redirect_path, notice: "เพิ่มคู่แข่งขันเรียบร้อยแล้ว"
  rescue ActiveRecord::RecordNotFound
    redirect_to manage_schedule_tournament_path(@tournament), alert: "ไม่พบรุ่นที่ระบุ"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to manage_schedule_tournament_path(@tournament), alert: e.record.errors.full_messages.join(", ")
  end

  def resolve_knockout_slots
    unless can_manage_registrations?(@tournament)
      return redirect_to knockout_tournament_path(@tournament), alert: I18n.t("sessions.flash.login_required")
    end

    division = @tournament.tournament_divisions.find(params[:division_id])
    
    # Get standings for each group
    standings_by_group = calculate_standings_for_division(division)
    
    # Get first round knockout matches
    first_round_matches = division.matches.knockout.where(round_number: 1)
    
    resolved_count = 0
    Match.transaction do
      first_round_matches.each do |match|
        home_resolved = resolve_slot_to_team(match.home_slot_label, standings_by_group, division)
        away_resolved = resolve_slot_to_team(match.away_slot_label, standings_by_group, division)
        
        update_attrs = {}
        if home_resolved && match.home_team_id.blank?
          update_attrs[:home_team_id] = home_resolved[:team_id]
        end
        if away_resolved && match.away_team_id.blank?
          update_attrs[:away_team_id] = away_resolved[:team_id]
        end
        
        if update_attrs.any?
          match.update!(update_attrs)
          resolved_count += 1
        end
      end
    end

    if resolved_count > 0
      redirect_to knockout_tournament_path(@tournament), notice: "Resolve ทีมจากตารางคะแนนเรียบร้อยแล้ว (#{resolved_count} คู่)"
    else
      redirect_to knockout_tournament_path(@tournament), notice: "ไม่มีคู่ที่ต้อง resolve หรือทีมถูกกำหนดไว้แล้ว"
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to knockout_tournament_path(@tournament), alert: "ไม่พบรุ่นที่ระบุ"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to knockout_tournament_path(@tournament), alert: e.record.errors.full_messages.join(", ")
  end

  private

  def set_tournament
    @tournament = Tournament.includes(:field, :organizer, :teams, :team_registrations, :tournament_divisions).find(params[:id])
  end

  def require_edit_permission
    unless can_edit_tournament?(@tournament)
      redirect_to tournaments_path, alert: I18n.t("sessions.flash.login_required")
    end
  end

  def require_pro_plan
    return

    return unless logged_in?
    return unless can_edit_tournament?(@tournament)
    return if admin?
    return if current_user&.respond_to?(:pro?) && current_user.pro?
    return if @tournament&.pro?
    return if @tournament&.competition_data_present?
    return if pro_owner?(@tournament)

    redirect_to tournament_path(@tournament), alert: "เมนูนี้รองรับเฉพาะแพ็กเกจ Pro (แพ็กเกจฟรีใช้งานได้เฉพาะ Info และ Team)"
  end

  def tournament_params
    params.require(:tournament).permit(
      :title,
      :description,
      :location_name,
      :city,
      :province,
      :line_id,
      :google_maps_url,
      :competition_date,
      :registration_open_on,
      :registration_close_on,
      :contact_phone,
      :team_size,
      :organizer_id,
      :field_id,
      images: [],
      tournament_divisions_attributes: [
        :id,
        :name,
        :entry_fee,
        :prize_amount,
        :match_format,
        :_destroy
      ]
    )
  end

  # เรียก auto-seed น็อคเอาท์ให้รุ่นที่พร้อมแล้วหลังบันทึกสกอร์
  def auto_seed_knockout_if_ready(division_ids)
    return nil if division_ids.blank?

    messages = []

    @tournament.tournament_divisions.where(id: division_ids).find_each do |division|
      group_matches   = division.matches.group_stage
      knockout_matches = division.matches.knockout

      next if group_matches.empty? || knockout_matches.empty?

      # ต้องกรอกสกอร์ครบทุกแมตช์รอบแบ่งกลุ่ม
      next if group_matches.where("home_score IS NULL OR away_score IS NULL").exists?

      # รองรับเฉพาะ knockout 4 หรือ 8 ทีม
      first_round_matches = knockout_matches.where(round_number: 1)
      bracket_size = first_round_matches.count * 2
      next unless [4, 8].include?(bracket_size)

      result = ::Tournaments::AutoSeedKnockoutService.new(
        division: division,
        bracket_size: bracket_size
      ).call

      if result.success?
        messages << "อัปเดตทีมที่เข้ารอบน็อคเอาท์ของรุ่น #{division.name} อัตโนมัติแล้ว"
      elsif result.message.present?
        messages << "ไม่สามารถจัดทีมเข้ารอบน็อคเอาท์ของรุ่น #{division.name}: #{result.message}"
      end
    end

    messages.join(" ") if messages.any?
  end

  def auto_advance_knockout_winners(division_ids)
    return nil if division_ids.blank?

    messages = []

    @tournament.tournament_divisions.where(id: division_ids).find_each do |division|
      result = ::Tournaments::AutoAdvanceKnockoutWinnersService.new(division: division).call

      next if result.success? && result.message.blank?

      if result.success?
        messages << "อัปเดตทีมในรอบน็อคเอาท์ถัดไปของรุ่น #{division.name} อัตโนมัติแล้ว"
      elsif result.message.present?
        messages << "ไม่สามารถอัปเดตทีมในรอบน็อคเอาท์ถัดไปของรุ่น #{division.name}: #{result.message}"
      end
    end

    messages.join(" ") if messages.any?
  end

  def calculate_standings_for_division(division)
    standings = {}
    
    division.groups.each do |group|
      group_matches = division.matches.group_stage.where(group: group)
                              .where.not(home_score: nil, away_score: nil)
      
      team_stats = Hash.new { |h, k| h[k] = { played: 0, won: 0, draw: 0, lost: 0, gf: 0, ga: 0, pts: 0, team_id: nil, team_name: nil } }
      
      # Get all teams in this group from matches
      group_matches.each do |m|
        if m.home_team_id.present?
          team_stats[m.home_team_id][:team_id] = m.home_team_id
          team_stats[m.home_team_id][:team_name] = m.home_name
        end
        if m.away_team_id.present?
          team_stats[m.away_team_id][:team_id] = m.away_team_id
          team_stats[m.away_team_id][:team_name] = m.away_name
        end
      end
      
      # Calculate stats
      group_matches.each do |m|
        next unless m.home_team_id.present? && m.away_team_id.present?
        
        home_id = m.home_team_id
        away_id = m.away_team_id
        home_score = m.home_score.to_i
        away_score = m.away_score.to_i
        
        team_stats[home_id][:played] += 1
        team_stats[home_id][:gf] += home_score
        team_stats[home_id][:ga] += away_score
        
        team_stats[away_id][:played] += 1
        team_stats[away_id][:gf] += away_score
        team_stats[away_id][:ga] += home_score
        
        if home_score > away_score
          team_stats[home_id][:won] += 1
          team_stats[home_id][:pts] += 3
          team_stats[away_id][:lost] += 1
        elsif home_score < away_score
          team_stats[away_id][:won] += 1
          team_stats[away_id][:pts] += 3
          team_stats[home_id][:lost] += 1
        else
          team_stats[home_id][:draw] += 1
          team_stats[home_id][:pts] += 1
          team_stats[away_id][:draw] += 1
          team_stats[away_id][:pts] += 1
        end
      end
      
      # Sort by points, then goal difference, then goals for
      sorted_teams = team_stats.values.sort_by { |t| [-t[:pts], -(t[:gf] - t[:ga]), -t[:gf]] }
      
      standings[group.name] = sorted_teams
    end
    
    standings
  end

  def resolve_slot_to_team(slot_label, standings_by_group, division)
    return nil if slot_label.blank?
    
    # Parse slot label like "1A", "2B", etc.
    match_data = slot_label.to_s.match(/^(\d+)([A-Z])$/i)
    return nil unless match_data
    
    rank = match_data[1].to_i
    group_name = match_data[2].upcase
    
    group_standings = standings_by_group[group_name]
    return nil unless group_standings && group_standings.size >= rank
    
    team = group_standings[rank - 1]
    return nil unless team && team[:team_id].present?
    
    { team_id: team[:team_id], team_name: team[:team_name] }
  end
end
