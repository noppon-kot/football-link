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

  def new
    @tournament = Tournament.new
  end

  def create
    @tournament = Tournament.new(tournament_params)
    # ชั่วคราว: ถ้ายังไม่ได้เลือกผู้จัด/สนาม ใช้ค่าเริ่มต้นจากข้อมูลที่มีอยู่
    @tournament.organizer ||= User.organizer.first || User.first
    @tournament.field     ||= Field.first

    if @tournament.save
      redirect_to @tournament, notice: "สร้างรายการแข่งเรียบร้อยแล้ว"
    else
      render :new, status: :unprocessable_entity
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
      :age_category,
      :team_size,
      :entry_fee,
      :prize_amount,
      :organizer_id,
      :field_id
    )
  end
end
