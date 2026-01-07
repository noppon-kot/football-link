class DashboardsController < ApplicationController
  before_action :require_login

  def show
    result = ::Dashboards::ShowService.new(
      current_user: current_user,
      params: params,
      admin: admin?
    ).call

    @tournaments = result.tournaments
  end
end
