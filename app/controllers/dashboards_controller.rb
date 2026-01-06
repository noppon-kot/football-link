class DashboardsController < ApplicationController
  before_action :require_login

  def show
    base_scope = if admin?
                   Tournament.all
                 else
                   current_user.organized_tournaments
                 end

    @tournaments = base_scope.includes(:field, :team_registrations)

    # filter by created_at period
    case params[:created_period]
    when "7_days"
      @tournaments = @tournaments.where("created_at >= ?", 7.days.ago)
    when "30_days"
      @tournaments = @tournaments.where("created_at >= ?", 30.days.ago)
    end

    # filter by status (pending/active)
    if params[:status].present? && Tournament.statuses.key?(params[:status])
      @tournaments = @tournaments.where(status: params[:status])
    end

    # filter by province
    if params[:province].present?
      @tournaments = @tournaments.where(province: params[:province])
    end

    # search by title
    if params[:q].present?
      q = "%#{params[:q].strip}%"
      @tournaments = @tournaments.where("title ILIKE ?", q)
    end

    @tournaments = @tournaments.order(created_at: :desc)
  end
end
