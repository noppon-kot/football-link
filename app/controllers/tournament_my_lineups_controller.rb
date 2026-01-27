require "set"

class TournamentMyLineupsController < ApplicationController
  before_action :require_login
  before_action :set_tournament
  before_action :set_entry
  before_action :require_entry_permission
  before_action :require_roster_submitted

  def index
    division_id = @entry.tournament_division_id

    @matches = Match
              .where(tournament_division_id: division_id)
              .where("home_team_id = :team_id OR away_team_id = :team_id", team_id: @entry.team_id)
              .includes(:home_team, :away_team)
              .order(Arel.sql("matches.kickoff_at ASC NULLS LAST"), :id)

    @match_side = {}
    @matches.each do |m|
      if m.home_team_id == @entry.team_id
        @match_side[m.id] = :home
      elsif m.away_team_id == @entry.team_id
        @match_side[m.id] = :away
      end
    end

    @lineup_by_match_id = MatchLineup
                          .where(match_id: @matches.map(&:id))
                          .select(:id, :match_id, :side, :submitted_at)
                          .index_by(&:match_id)
  end

  def show
    @match = Match.includes(:home_team, :away_team, :tournament_division).find(params[:match_id])
    if @match.tournament_division&.tournament_id != @tournament.id
      raise ActiveRecord::RecordNotFound
    end

    unless @match.tournament_division_id == @entry.tournament_division_id
      raise ActiveRecord::RecordNotFound
    end

    @side = if @match.home_team_id == @entry.team_id
              :home
            elsif @match.away_team_id == @entry.team_id
              :away
            else
              raise ActiveRecord::RecordNotFound
            end

    @lineup = @match.match_lineups.find_or_create_by!(side: @side)
    @lineup.update!(team_registration_id: @entry.id) if @lineup.team_registration_id != @entry.id

    @players = @entry.tournament_players.order(:full_name, :id)
    player_ids = @players.map(&:id)

    yellow_counts = MatchEvent
                    .joins(match: :tournament_division)
                    .where(tournament_player_id: player_ids)
                    .where(event_type: :yellow_card)
                    .where(tournament_divisions: { tournament_id: @tournament.id })
                    .group(:tournament_player_id)
                    .count

    @yellow_count_by_player_id = yellow_counts

    @starter_id_set = @lineup.match_lineup_players.where(role: :starter).pluck(:tournament_player_id).to_set
    @competition_year = @tournament.competition_date&.year
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
    return if can_manage_registrations?(@tournament)
    return if @entry.team_registration_managers.where(user_id: current_user.id).exists?
    return if @entry.manager_user_id == current_user.id

    redirect_to teams_tournament_path(@tournament), alert: I18n.t("sessions.flash.login_required")
  end

  def require_roster_submitted
    return if admin?
    return if can_manage_registrations?(@tournament)
    return if @entry.respond_to?(:roster_locked?) && @entry.roster_locked?

    redirect_to my_entry_players_tournament_path(@tournament, team_registration_id: @entry.id),
                alert: "ต้องส่งรายชื่อนักเตะก่อน จึงจะส่งรายชื่อตัวจริงได้"
  end
end
