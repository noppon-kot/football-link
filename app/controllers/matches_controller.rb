class MatchesController < ApplicationController
  before_action :require_login
  before_action :set_match
  before_action :require_manage_permission

  def update
    if @match.update(match_params)
      tournament = @match.tournament_division.tournament
      redirect_to fixture_tournament_path(tournament), notice: "บันทึกสกอร์เรียบร้อยแล้ว"
    else
      tournament = @match.tournament_division.tournament
      redirect_to fixture_tournament_path(tournament), alert: @match.errors.full_messages.join(", ")
    end
  end

  private

  def set_match
    @match = Match.find(params[:id])
  end

  def require_manage_permission
    tournament = @match.tournament_division.tournament
    unless can_manage_registrations?(tournament)
      redirect_to tournament, alert: I18n.t("sessions.flash.login_required")
    end
  end

  def match_params
    params.require(:match).permit(:home_score, :away_score)
  end
end
