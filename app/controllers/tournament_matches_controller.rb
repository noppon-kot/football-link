class TournamentMatchesController < ApplicationController
  skip_before_action :require_login, only: [:show]

  before_action :set_tournament
  before_action :set_match
  before_action :set_entries
  before_action :set_lineups

  def show
    @can_manage_tournament = can_manage_registrations?(@tournament)

    @home_roster_submitted = @home_entry&.respond_to?(:roster_locked?) && @home_entry.roster_locked?
    @away_roster_submitted = @away_entry&.respond_to?(:roster_locked?) && @away_entry.roster_locked?

    @home_players = if @can_manage_tournament && @home_entry && @home_roster_submitted
                      @home_entry.tournament_players.order(:full_name, :id)
                    else
                      TournamentPlayer.none
                    end

    @away_players = if @can_manage_tournament && @away_entry && @away_roster_submitted
                      @away_entry.tournament_players.order(:full_name, :id)
                    else
                      TournamentPlayer.none
                    end

    @match_events = @match.match_events.includes(tournament_player: :team_registration).order(:id)

    @home_lineup_players = @home_lineup.match_lineup_players.includes(:tournament_player).to_a
    @away_lineup_players = @away_lineup.match_lineup_players.includes(:tournament_player).to_a

    lineup_player_ids = (@home_lineup_players + @away_lineup_players).map { |lp| lp.tournament_player_id }.compact.uniq
    @yellow_count_by_player_id = {}
    if lineup_player_ids.any?
      @yellow_count_by_player_id = MatchEvent
                                  .joins(match: :tournament_division)
                                  .where(tournament_player_id: lineup_player_ids)
                                  .where(event_type: :yellow_card)
                                  .where(tournament_divisions: { tournament_id: @tournament.id })
                                  .group(:tournament_player_id)
                                  .count
    end

    @competition_year = @tournament.competition_date&.year
  end

  def update_score
    require_login
    unless can_manage_registrations?(@tournament)
      return redirect_to match_tournament_path(@tournament, match_id: @match.id), alert: I18n.t("sessions.flash.login_required")
    end

    permitted = params.require(:match).permit(:home_score, :away_score, :penalty_winner_side, :video_url)

    update_attrs = permitted.to_h
    
    # Handle penalty winner side
    if update_attrs.key?("penalty_winner_side")
      winner_side = update_attrs["penalty_winner_side"].presence
      update_attrs["decided_by_penalty"] = winner_side.present?
    end

    if @match.update(update_attrs)
      redirect_to match_tournament_path(@tournament, match_id: @match.id), notice: "บันทึกสกอร์เรียบร้อยแล้ว"
    else
      redirect_to match_tournament_path(@tournament, match_id: @match.id), alert: @match.errors.full_messages.join(", ")
    end
  end

  def update_images
    require_login
    unless can_manage_registrations?(@tournament)
      return redirect_to match_tournament_path(@tournament, match_id: @match.id), alert: I18n.t("sessions.flash.login_required")
    end

    permitted = params.require(:match).permit(images: []).to_h

    # ถ้าไม่ได้เลือกไฟล์รูปใหม่ อย่าไปแตะ images เดิม
    if permitted.key?("images")
      images_val = permitted["images"]
      if images_val.blank? || (images_val.is_a?(Array) && images_val.all?(&:blank?))
        permitted.delete("images")
      end
    end

    ok = false
    ActiveRecord::Base.transaction do
      # มีการอัปโหลดรูปใหม่: แทนที่รูปเดิม
      if permitted.key?("images")
        @match.images_attachments.destroy_all if @match.images.attached?
      end

      ok = @match.update(permitted)
      raise ActiveRecord::Rollback unless ok
    end

    if ok
      redirect_to match_tournament_path(@tournament, match_id: @match.id), notice: "อัปโหลดรูปเรียบร้อยแล้ว"
    else
      redirect_to match_tournament_path(@tournament, match_id: @match.id), alert: @match.errors.full_messages.join(", ")
    end
  end

  def submit_lineup
    require_login

    lineup = params[:side].to_s == "away" ? @away_lineup : @home_lineup
    entry = params[:side].to_s == "away" ? @away_entry : @home_entry

    unless entry
      return redirect_to match_tournament_path(@tournament, match_id: @match.id), alert: "ยังไม่สามารถส่งรายชื่อได้ (ทีมยังไม่ถูกกำหนด)"
    end

    unless can_manage_registrations?(@tournament) || can_manage_entry?(entry)
      return redirect_to match_tournament_path(@tournament, match_id: @match.id), alert: I18n.t("sessions.flash.login_required")
    end

    if !can_manage_registrations?(@tournament) && !entry.roster_locked?
      return redirect_to match_tournament_path(@tournament, match_id: @match.id), alert: "ต้องส่งรายชื่อนักกีฬาก่อน จึงจะยืนยันรายชื่อในแมตช์ได้"
    end

    kickoff_at = @match.kickoff_at
    if !can_manage_registrations?(@tournament) && kickoff_at.present? && Time.zone.now >= kickoff_at
      return redirect_to match_tournament_path(@tournament, match_id: @match.id), alert: "เริ่มแข่งขันแล้ว ไม่สามารถแก้ไขรายชื่อตัวจริงได้"
    end

    starter_ids = Array(params.dig(:lineup, :starter_ids)).map(&:to_i).uniq

    allowed_ids = entry.tournament_players.pluck(:id)
    starter_ids &= allowed_ids

    MatchLineup.transaction do
      lineup.update!(team_registration: entry)

      lineup.match_lineup_players.delete_all

      starter_ids.each do |pid|
        lineup.match_lineup_players.create!(tournament_player_id: pid, role: :starter)
      end

      lineup.update!(
        submitted_by_user: current_user,
        submitted_at: Time.zone.now,
        locked: (can_manage_registrations?(@tournament) ? lineup.locked? : false)
      )
    end

    redirect_to match_tournament_path(@tournament, match_id: @match.id), notice: "ส่งรายชื่อเรียบร้อยแล้ว"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to match_tournament_path(@tournament, match_id: @match.id), alert: e.record.errors.full_messages.join(", ")
  end

  def unlock_lineup
    require_login
    unless can_manage_registrations?(@tournament)
      return redirect_to match_tournament_path(@tournament, match_id: @match.id), alert: I18n.t("sessions.flash.login_required")
    end

    lineup = params[:side].to_s == "away" ? @away_lineup : @home_lineup
    lineup.update!(locked: false, submitted_by_user: nil, submitted_at: nil)

    redirect_to match_tournament_path(@tournament, match_id: @match.id), notice: "ปลดล็อกรายชื่อเรียบร้อยแล้ว"
  end

  def create_event
    require_login
    unless can_manage_registrations?(@tournament)
      return redirect_to match_tournament_path(@tournament, match_id: @match.id), alert: I18n.t("sessions.flash.login_required")
    end

    permitted = params.require(:match_event).permit(:event_type, :tournament_player_id)
    player = TournamentPlayer.find_by(id: permitted[:tournament_player_id])
    unless player
      return redirect_to match_tournament_path(@tournament, match_id: @match.id), alert: "ไม่พบนักเตะ"
    end

    unless [@home_entry&.id, @away_entry&.id].compact.include?(player.team_registration_id)
      return redirect_to match_tournament_path(@tournament, match_id: @match.id), alert: "นักเตะไม่อยู่ในแมตช์นี้"
    end

    event = @match.match_events.new(event_type: permitted[:event_type], tournament_player: player)
    if event.save
      redirect_to match_tournament_path(@tournament, match_id: @match.id), notice: "เพิ่มเหตุการณ์เรียบร้อยแล้ว"
    else
      redirect_to match_tournament_path(@tournament, match_id: @match.id), alert: event.errors.full_messages.join(", ")
    end
  end

  def destroy_event
    require_login
    unless can_manage_registrations?(@tournament)
      return redirect_to match_tournament_path(@tournament, match_id: @match.id), alert: I18n.t("sessions.flash.login_required")
    end

    event = @match.match_events.find_by(id: params[:event_id])
    unless event
      return redirect_to match_tournament_path(@tournament, match_id: @match.id), alert: "ไม่พบเหตุการณ์"
    end

    event.destroy
    redirect_to match_tournament_path(@tournament, match_id: @match.id), notice: "ลบเหตุการณ์เรียบร้อยแล้ว"
  end

  private

  def set_tournament
    tournament_id = params[:tournament_id].presence || params[:id]
    @tournament = Tournament.find(tournament_id)
  end

  def set_match
    @match = Match.includes(:tournament_division, :home_team, :away_team).find(params[:match_id])

    if @match.tournament_division&.tournament_id != @tournament.id
      raise ActiveRecord::RecordNotFound
    end
  end

  def set_entries
    division_id = @match.tournament_division_id

    @home_entry = if @match.home_team_id.present?
                    TeamRegistration.find_by(tournament_id: @tournament.id, tournament_division_id: division_id, team_id: @match.home_team_id)
                  end

    @away_entry = if @match.away_team_id.present?
                    TeamRegistration.find_by(tournament_id: @tournament.id, tournament_division_id: division_id, team_id: @match.away_team_id)
                  end
  end

  def set_lineups
    @home_lineup = @match.match_lineups.find_or_create_by!(side: :home)
    @away_lineup = @match.match_lineups.find_or_create_by!(side: :away)
  end

  def can_manage_entry?(entry)
    return false unless current_user
    return true if entry.team_registration_managers.where(user_id: current_user.id).exists?
    entry.manager_user_id == current_user.id
  end
end
