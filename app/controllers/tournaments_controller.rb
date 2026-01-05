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
    @tournament = Tournament.includes(:field, :organizer, :teams, :team_registrations, :tournament_divisions).find(params[:id])
  end

  def new
    @tournament = Tournament.new
    3.times { @tournament.tournament_divisions.build }
  end

  def edit
    @tournament = Tournament.includes(:tournament_divisions).find(params[:id])
    # ให้มีแถวกรอกรุ่นอย่างน้อย 3 แถวเสมอ ระหว่างแก้ไข
    missing = 3 - @tournament.tournament_divisions.size
    missing.times { @tournament.tournament_divisions.build } if missing.positive?
  end

  def create
    service = ::Tournaments::CreateService.new(tournament_params)
    @tournament = service.tournament

    if service.call
      redirect_to @tournament, notice: I18n.t("tournaments.flash.create_success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @tournament = Tournament.find(params[:id])
    service = ::Tournaments::UpdateService.new(@tournament, tournament_params)

    if service.call
      redirect_to @tournament, notice: I18n.t("tournaments.flash.update_success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def tournament_params
    params.require(:tournament).permit(
      :title,
      :description,
      :location_name,
      :city,
      :province,
      :team_size,
      :organizer_id,
      :field_id,
      tournament_divisions_attributes: [
        :id,
        :name,
        :entry_fee,
        :prize_amount,
        :_destroy
      ]
    )
  end
end
