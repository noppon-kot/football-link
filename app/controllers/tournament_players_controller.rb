class TournamentPlayersController < ApplicationController
  before_action :require_login
  before_action :set_tournament
  before_action :set_entry
  before_action :require_entry_permission
  before_action :require_roster_unlocked, only: [:new, :create, :edit, :update, :destroy]
  before_action :set_player, only: [:edit, :update, :destroy]

  before_action :set_player, only: [:clear_yellow_cards, :clear_red_cards]

  before_action :require_manage_tournament, only: [:clear_yellow_cards, :clear_red_cards]

  skip_before_action :require_login, only: [:public_index]
  skip_before_action :require_entry_permission, only: [:public_index]

  def index
    @players = @entry.tournament_players.order(:full_name, :id)
    load_event_summaries
  end

  def public_index
    @public_view = true
    @players = @entry.tournament_players.order(:full_name, :id)
    load_event_summaries
    render :index
  end

  def clear_yellow_cards
    events_scope_for_player(event_type: :yellow_card).destroy_all
    redirect_back fallback_location: team_players_tournament_path(@tournament, team_registration_id: @entry.id), notice: "ล้างใบเหลืองเรียบร้อยแล้ว"
  end

  def clear_red_cards
    events_scope_for_player(event_type: :red_card).destroy_all
    redirect_back fallback_location: team_players_tournament_path(@tournament, team_registration_id: @entry.id), notice: "ล้างใบแดงเรียบร้อยแล้ว"
  end

  def new
    @player = @entry.tournament_players.new
  end

  def create
    @player = @entry.tournament_players.new(player_params)

    if @player.save
      redirect_to my_entry_players_tournament_path(@tournament, team_registration_id: @entry.id), notice: "เพิ่มนักกีฬาเรียบร้อยแล้ว"
    else
      flash.now[:alert] = @player.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if player_params[:photo].present?
      @player.photo.purge if @player.photo.attached?
      @player.photo.attach(player_params[:photo])
    end

    if @player.update(player_params.except(:photo))
      redirect_to my_entry_players_tournament_path(@tournament, team_registration_id: @entry.id), notice: "บันทึกนักกีฬาเรียบร้อยแล้ว"
    else
      flash.now[:alert] = @player.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @player.photo.purge if @player.photo.attached?
    @player.destroy
    redirect_to my_entry_players_tournament_path(@tournament, team_registration_id: @entry.id), notice: "ลบนักกีฬาเรียบร้อยแล้ว"
  end

  private

  def set_tournament
    tournament_id = params[:tournament_id].presence || params[:id]
    @tournament = Tournament.find(tournament_id)
  end

  def set_entry
    @entry = @tournament.team_registrations.find(params[:team_registration_id])
  end

  def set_player
    @player = @entry.tournament_players.find(params[:id])
  end

  def require_manage_tournament
    return if can_manage_registrations?(@tournament)
    redirect_to teams_tournament_path(@tournament), alert: I18n.t("sessions.flash.login_required")
  end

  def load_event_summaries
    player_ids = @players.map(&:id)
    @player_events = MatchEvent
                   .joins(match: :tournament_division)
                   .includes(:match, :tournament_player)
                   .where(tournament_player_id: player_ids)
                   .where(event_type: [:goal, :yellow_card, :red_card])
                   .where(tournament_divisions: { tournament_id: @tournament.id })
                   .order("matches.kickoff_at ASC NULLS LAST", "matches.id ASC", "match_events.id ASC")

    @events_by_player = @player_events.group_by(&:tournament_player_id)
  end

  def events_scope_for_player(event_type:)
    MatchEvent
      .joins(match: :tournament_division)
      .where(tournament_player_id: @player.id)
      .where(event_type: event_type)
      .where(tournament_divisions: { tournament_id: @tournament.id })
  end

  def require_entry_permission
    return if admin?
    return if can_manage_registrations?(@tournament)
    return if @entry.team_registration_managers.where(user_id: current_user.id).exists?
    return if @entry.manager_user_id == current_user.id

    redirect_to teams_tournament_path(@tournament), alert: I18n.t("sessions.flash.login_required")
  end

  def require_roster_unlocked
    return if can_manage_registrations?(@tournament)
    return unless @entry.roster_locked?

    redirect_to my_entry_players_tournament_path(@tournament, team_registration_id: @entry.id), alert: "ส่งรายชื่อนักกีฬาแล้ว ไม่สามารถแก้ไขได้"
  end

  def player_params
    params.require(:tournament_player).permit(:full_name, :birth_date, :jersey_number, :active, :photo)
  end
end
