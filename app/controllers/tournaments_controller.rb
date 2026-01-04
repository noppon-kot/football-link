class TournamentsController < ApplicationController
  def index
    @age_categories = Tournament.distinct.order(:age_category).pluck(:age_category).compact
    @provinces      = Tournament.distinct.order(:province).pluck(:province).compact

    @tournaments = Tournament.includes(:field, :organizer).order(created_at: :desc)

    if params[:q].present?
      q = "%#{params[:q].strip}%"
      @tournaments = @tournaments.where(
        "title ILIKE :q OR location_name ILIKE :q OR city ILIKE :q OR province ILIKE :q",
        q: q
      )
    end

    if params[:age_category].present?
      @tournaments = @tournaments.where(age_category: params[:age_category])
    end

    if params[:province].present?
      @tournaments = @tournaments.where(province: params[:province])
    end

    @current_page = params[:page].to_i
    @current_page = 1 if @current_page < 1
    per_page = 6
    @total_pages = (@tournaments.count / per_page.to_f).ceil
    @tournaments = @tournaments.offset((@current_page - 1) * per_page).limit(per_page)
  end

  def show
    @tournament = Tournament.includes(:field, :organizer, :teams, :team_registrations).find(params[:id])
  end
end
