class DashboardsController < ApplicationController
  before_action :require_login

  def show
    @tournaments = current_user.organized_tournaments
                               .includes(:field, :team_registrations)
                               .order(created_at: :desc)
  end
end
