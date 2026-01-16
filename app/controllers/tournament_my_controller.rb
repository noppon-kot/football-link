class TournamentMyController < ApplicationController
  before_action :require_login
  before_action :set_tournament

  def show
    @entries = @tournament.team_registrations
                         .left_joins(:team_registration_managers)
                         .where("team_registration_managers.user_id = ? OR team_registrations.manager_user_id = ?", current_user.id, current_user.id)
                         .left_joins(:tournament_players)
                         .select("team_registrations.*, COUNT(tournament_players.id) AS players_count")
                         .includes(:team, :tournament_division)
                         .group("team_registrations.id")
                         .order(created_at: :desc)
  end

  private

  def set_tournament
    @tournament = Tournament.find(params[:id])
  end
end
