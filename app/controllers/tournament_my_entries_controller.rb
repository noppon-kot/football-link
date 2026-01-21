class TournamentMyEntriesController < ApplicationController
  before_action :require_login
  before_action :set_tournament
  before_action :set_entry
  before_action :require_entry_permission

  def show
  end

  def submit_roster
    if @entry.roster_locked?
      return redirect_to my_entry_players_tournament_path(@tournament, team_registration_id: @entry.id), notice: "ส่งรายชื่อแล้ว"
    end

    if @entry.tournament_players.count.zero?
      return redirect_to my_entry_players_tournament_path(@tournament, team_registration_id: @entry.id), alert: "ยังไม่มีนักกีฬาในทีมนี้"
    end

    @entry.update!(
      roster_locked: true,
      roster_submitted_at: Time.zone.now,
      roster_submitted_by_user_id: current_user.id
    )

    redirect_to my_entry_players_tournament_path(@tournament, team_registration_id: @entry.id), notice: "ส่งรายชื่อนักกีฬาเรียบร้อยแล้ว"
  end

  def unlock_roster
    unless can_manage_registrations?(@tournament)
      return redirect_to my_entry_players_tournament_path(@tournament, team_registration_id: @entry.id), alert: I18n.t("sessions.flash.login_required")
    end

    @entry.update!(roster_locked: false, roster_submitted_at: nil, roster_submitted_by_user_id: nil)
    redirect_to my_entry_players_tournament_path(@tournament, team_registration_id: @entry.id), notice: "ปลดล็อครายชื่อนักกีฬาเรียบร้อยแล้ว"
  end

  private

  def set_tournament
    tournament_id = params[:tournament_id].presence || params[:id]
    @tournament = Tournament.find(tournament_id)
  end

  def set_entry
    @entry = @tournament.team_registrations.find(params[:team_registration_id])
  end

  def require_entry_permission
    return if admin?
    return if @entry.team_registration_managers.where(user_id: current_user.id).exists?
    return if @entry.manager_user_id == current_user.id

    redirect_to teams_tournament_path(@tournament), alert: I18n.t("sessions.flash.login_required")
  end
end
