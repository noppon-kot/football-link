class TournamentMyController < ApplicationController
  before_action :require_login
  before_action :set_tournament

  def show
    redirect_to teams_tournament_path(@tournament)
  end

  private

  def set_tournament
    @tournament = Tournament.find(params[:id])
  end
end
