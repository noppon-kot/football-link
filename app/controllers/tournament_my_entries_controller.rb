class TournamentMyEntriesController < ApplicationController
  before_action :require_login
  before_action :set_tournament
  before_action :set_entry
  before_action :require_entry_permission

  def show
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

    redirect_to my_tournament_path(@tournament), alert: I18n.t("sessions.flash.login_required")
  end
end
