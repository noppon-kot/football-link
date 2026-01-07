module Dashboards
  class ShowService
    Result = Struct.new(:tournaments, keyword_init: true)

    def initialize(current_user:, params:, admin: false)
      @current_user = current_user
      @params       = params
      @admin        = admin
    end

    def call
      base_scope = if @admin
                     Tournament.all
                   else
                     @current_user.organized_tournaments
                   end

      tournaments = base_scope.includes(:field, :team_registrations)

      case @params[:created_period]
      when "7_days"
        tournaments = tournaments.where("created_at >= ?", 7.days.ago)
      when "30_days"
        tournaments = tournaments.where("created_at >= ?", 30.days.ago)
      end

      if @params[:status].present? && Tournament.statuses.key?(@params[:status])
        tournaments = tournaments.where(status: @params[:status])
      end

      if @params[:province].present?
        tournaments = tournaments.where(province: @params[:province])
      end

      if @params[:q].present?
        q = "%#{@params[:q].strip}%"
        tournaments = tournaments.where("title ILIKE ?", q)
      end

      tournaments = tournaments.order(created_at: :desc)

      Result.new(tournaments: tournaments)
    end
  end
end
