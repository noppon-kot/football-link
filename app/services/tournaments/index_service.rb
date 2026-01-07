module Tournaments
  class IndexService
    Result = Struct.new(
      :age_categories,
      :provinces,
      :tournaments,
      :current_page,
      :total_pages,
      keyword_init: true
    )

    def initialize(params:, current_user:, admin: false)
      @params       = params
      @current_user = current_user
      @admin        = admin
    end

    def call
      age_categories = Tournament.distinct.order(:age_category).pluck(:age_category).compact
      provinces      = Tournament.distinct.order(:province).pluck(:province).compact

      base_scope = if @admin
                     Tournament.all
                   else
                     Tournament.active_for_search
                   end

      tournaments = base_scope
                      .includes(:field, :organizer, :team_registrations)
                      .order(created_at: :desc)

      if @params[:q].present?
        q = "%#{@params[:q].strip}%"
        tournaments = tournaments.where(
          "title ILIKE :q OR location_name ILIKE :q OR city ILIKE :q OR province ILIKE :q",
          q: q
        )
      end

      if @params[:age_category].present?
        tournaments = tournaments.where(age_category: @params[:age_category])
      end

      if @params[:province].present?
        tournaments = tournaments.where(province: @params[:province])
      end

      current_page = @params[:page].to_i
      current_page = 1 if current_page < 1
      per_page = 10
      total_pages = (tournaments.count / per_page.to_f).ceil
      tournaments = tournaments.offset((current_page - 1) * per_page).limit(per_page)

      Result.new(
        age_categories: age_categories,
        provinces: provinces,
        tournaments: tournaments,
        current_page: current_page,
        total_pages: total_pages
      )
    end
  end
end
