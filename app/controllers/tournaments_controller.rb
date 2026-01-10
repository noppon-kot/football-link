require "set"

class TournamentsController < ApplicationController
  # ให้ทุกคนเข้า view ได้ทุกเมนูของทัวร์นาเมนต์ ยกเว้น action ที่แก้ไขข้อมูล
  before_action :require_login, except: [:index, :show, :teams, :groups, :fixture, :table, :knockout]
  before_action :set_tournament, only: [:show, :edit, :update, :approve, :teams, :groups, :fixture, :table, :knockout, :generate_knockout, :generate_mock_schedule, :assign_slot_teams, :update_points, :update_scores, :destroy]
  before_action :require_edit_permission, only: [:edit, :update]
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

  def groups
    # ใช้ @tournament จาก set_tournament และ logic แบ่งสาย/จัดทีมลงสายใน view ใหม่
  end

  def fixture
    # ใช้ @tournament จาก set_tournament และ logic เดิมใน view สำหรับตารางแข่งขัน
  end

  def table
    # ใช้ @tournament จาก set_tournament และภายหลังจะเพิ่ม logic คำนวณตารางคะแนน
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

    competition_mode = params[:competition_mode].presence || "group_with_knockout"
    target_path = groups_tournament_path(@tournament)

    division = @tournament.tournament_divisions.find_by(id: params[:division_id])
    unless division
      return redirect_to target_path, alert: "ไม่พบรุ่นการแข่งขันที่เลือก"
    end

    if competition_mode == "knockout_only"
      # โหมดน็อคเอาท์อย่างเดียว: ไม่สร้างรอบแบ่งกลุ่ม สร้างเฉพาะรอบน็อคเอาท์จากจำนวนทีมที่มีอยู่
      total_teams = division.team_registrations.distinct.count(:team_id)
      if total_teams.zero?
        return redirect_to target_path, alert: "รุ่นนี้ยังไม่มีทีม ไม่สามารถสร้างรอบน็อคเอาท์ได้"
      end

      # ล้างข้อมูลรอบแบ่งกลุ่มเดิมทิ้งทั้งหมดของรุ่นนี้ (ถ้ามี) แล้วสร้างสาย A/B ใหม่
      division.matches.group_stage.delete_all
      division.groups.delete_all

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

    matches_params = params[:matches] || {}
    affected_division_ids = Set.new

    Match.transaction do
      matches_params.each do |match_id, attrs|
        match = Match.find_by(id: match_id)
        next unless match

        permitted = attrs.permit(:home_score, :away_score, :kickoff_at, :penalty_winner_side)

        update_attrs = {}

        # วันเวลาแข่ง
        update_attrs[:kickoff_at] = permitted[:kickoff_at] if permitted[:kickoff_at].present?

        # สกอร์: ต้องกรอกทั้งสองฝั่งถึงจะบันทึก
        home_score = permitted[:home_score]
        away_score = permitted[:away_score]
        scores_changed = false

        if home_score.present? || away_score.present?
          next if home_score.blank? || away_score.blank?

          update_attrs[:home_score] = home_score
          update_attrs[:away_score] = away_score
          scores_changed = true
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

    notice_msg = ["บันทึกสกอร์เรียบร้อยแล้ว", auto_seed_message, advance_message].compact.join(" ")
    redirect_to fixture_tournament_path(@tournament), notice: notice_msg
  rescue ActiveRecord::RecordInvalid => e
    redirect_to fixture_tournament_path(@tournament), alert: e.record.errors.full_messages.join(", ")
  end

  def new
    @tournament = Tournament.new
    if current_user
      @tournament.contact_phone ||= current_user.phone
      @tournament.line_id       ||= current_user.line_id
    end
    @tournament.tournament_divisions.build
  end

  def edit
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
      redirect_to @tournament, notice: I18n.t("tournaments.flash.create_success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @tournament = Tournament.find(params[:id])
    permitted = tournament_params.to_h

    # ถ้าไม่ได้เลือกไฟล์รูปใหม่ อย่าไปแตะ images เดิม
    if permitted.key?("images")
      images_val = permitted["images"]
      if images_val.blank? || (images_val.is_a?(Array) && images_val.all?(&:blank?))
        permitted.delete("images")
      end
    end

    service = ::Tournaments::UpdateService.new(@tournament, permitted)

    if service.call
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

  private

  def set_tournament
    @tournament = Tournament.includes(:field, :organizer, :teams, :team_registrations, :tournament_divisions).find(params[:id])
  end

  def require_edit_permission
    unless can_edit_tournament?(@tournament)
      redirect_to tournaments_path, alert: I18n.t("sessions.flash.login_required")
    end
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
end
