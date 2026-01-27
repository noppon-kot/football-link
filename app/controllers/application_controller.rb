class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :current_user, :logged_in?, :admin?, :can_create_tournaments?, :can_edit_tournament?, :can_manage_registrations?, :pro_owner?

  before_action :require_login
  before_action :set_global_search_filters

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def logged_in?
    current_user.present?
  end

  def admin?
    current_user&.organizer?
  end

  def can_create_tournaments?
    logged_in?
  end

  def can_edit_tournament?(tournament)
    return false unless logged_in?
    return true if admin?
    return true if tournament.organizer_id == current_user.id
    TournamentStaff.where(tournament_id: tournament.id, user_id: current_user.id).exists?
  end

  def can_manage_registrations?(tournament)
    can_edit_tournament?(tournament)
  end

  def pro_owner?(tournament)
    return false unless logged_in?
    return false unless current_user.respond_to?(:pro?) && current_user.pro?
    tournament.organizer_id == current_user.id
  end

  def require_login
    return if logged_in?

    session[:return_to] = request.fullpath
    redirect_to login_path, alert: I18n.t("sessions.flash.login_required")
  end

  def set_global_search_filters
    @search_age_categories = Tournament.distinct.order(:age_category).pluck(:age_category).compact.reject(&:blank?)
    @search_provinces = Tournament.distinct.order(:province).pluck(:province).compact.reject(&:blank?)
  rescue ActiveRecord::StatementInvalid
    @search_age_categories = []
    @search_provinces = []
  end
end
