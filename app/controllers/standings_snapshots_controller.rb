require "base64"
require "stringio"

class StandingsSnapshotsController < ApplicationController
  skip_before_action :require_login, only: [:show]

  before_action :set_tournament

  def show
    division = @tournament.tournament_divisions.find_by(id: params[:division_id])
    return render json: { url: nil }, status: :not_found unless division

    group_id = params[:group_id].presence
    snapshot = StandingsSnapshot.find_by(tournament_division_id: division.id, group_id: group_id)
    return render json: { url: nil }, status: :not_found unless snapshot&.image&.attached?

    render json: {
      url: Rails.application.routes.url_helpers.rails_blob_path(snapshot.image, disposition: "attachment", only_path: true),
      generated_at: snapshot.generated_at,
      updated_at: snapshot.updated_at
    }
  end

  def create
    require_login
    unless can_manage_registrations?(@tournament)
      return render json: { error: I18n.t("sessions.flash.login_required") }, status: :forbidden
    end

    division = @tournament.tournament_divisions.find_by(id: params[:division_id])
    return render json: { error: "invalid_division" }, status: :unprocessable_entity unless division

    group_id = params[:group_id].presence
    if group_id.present?
      group = division.groups.find_by(id: group_id)
      return render json: { error: "invalid_group" }, status: :unprocessable_entity unless group
    end

    data_url = params[:image_data].to_s
    unless data_url.start_with?("data:image/png;base64,")
      return render json: { error: "invalid_image_data" }, status: :unprocessable_entity
    end

    base64 = data_url.split(",", 2)[1]
    raw = Base64.decode64(base64)

    snapshot = StandingsSnapshot.find_or_initialize_by(tournament_division_id: division.id, group_id: group_id)
    snapshot.generated_at = Time.zone.now
    snapshot.save!

    snapshot.image.purge if snapshot.image.attached?
    filename = if group_id.present?
                 "standings_div_#{division.id}_group_#{group_id}.png"
               else
                 "standings_div_#{division.id}.png"
               end
    snapshot.image.attach(
      io: StringIO.new(raw),
      filename: filename,
      content_type: "image/png"
    )

    render json: { ok: true }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
  end

  def card
    require_login
    unless can_manage_registrations?(@tournament)
      return head :forbidden
    end

    @division = @tournament.tournament_divisions.find(params[:division_id])
    @group = @division.groups.find_by(id: params[:group_id]) if params[:group_id].present?

    matches = Match.where(tournament_division_id: @division.id)
    matches = matches.where(group_id: @group.id) if @group.present?

    @group_matches = matches.includes(:home_team, :away_team).to_a
    @team_ids = (@group_matches.map(&:home_team_id) + @group_matches.map(&:away_team_id)).compact.uniq

    win_pts  = @division.respond_to?(:points_win)  ? @division.points_win  : 3
    draw_pts = @division.respond_to?(:points_draw) ? @division.points_draw : 1
    loss_pts = @division.respond_to?(:points_loss) ? @division.points_loss : 0
    draw_mode = @division.respond_to?(:draw_mode) ? (@division.draw_mode.presence || "normal") : "normal"
    pk_win_pts  = @division.respond_to?(:points_pk_win)  && @division.points_pk_win.present?  ? @division.points_pk_win  : draw_pts
    pk_loss_pts = @division.respond_to?(:points_pk_loss) && @division.points_pk_loss.present? ? @division.points_pk_loss : draw_pts

    stats = {}
    @team_ids.each do |tid|
      stats[tid] = { played: 0, won: 0, draw: 0, lost: 0, gf: 0, ga: 0, pts: 0 }
    end

    @group_matches.each do |match|
      next if match.home_team_id.blank? || match.away_team_id.blank?
      next unless match.home_score.present? && match.away_score.present?

      h_id = match.home_team_id
      a_id = match.away_team_id
      hs  = match.home_score.to_i
      as  = match.away_score.to_i

      stats[h_id][:played] += 1
      stats[a_id][:played] += 1
      stats[h_id][:gf] += hs; stats[h_id][:ga] += as
      stats[a_id][:gf] += as; stats[a_id][:ga] += hs

      if hs > as
        stats[h_id][:won]  += 1; stats[h_id][:pts] += win_pts
        stats[a_id][:lost] += 1; stats[a_id][:pts] += loss_pts
      elsif hs < as
        stats[a_id][:won]  += 1; stats[a_id][:pts] += win_pts
        stats[h_id][:lost] += 1; stats[h_id][:pts] += loss_pts
      else
        if draw_mode == "pk" && match.decided_by_penalty && match.penalty_winner_side.present?
          winner_id, loser_id = match.penalty_winner_side == "home" ? [h_id, a_id] : [a_id, h_id]
          stats[winner_id][:draw] += 1; stats[winner_id][:pts] += pk_win_pts
          stats[loser_id][:draw]  += 1; stats[loser_id][:pts]  += pk_loss_pts
        else
          stats[h_id][:draw] += 1; stats[h_id][:pts] += draw_pts
          stats[a_id][:draw] += 1; stats[a_id][:pts] += draw_pts
        end
      end
    end

    @sorted = @team_ids.map { |tid| [tid, stats[tid]] }
                 .sort_by { |tid, s| [-s[:pts], -s[:gf], Team.find(tid).name] }

    render layout: false
  end

  private

  def set_tournament
    tournament_id = params[:tournament_id].presence || params[:id]
    @tournament = Tournament.find(tournament_id)
  end
end
