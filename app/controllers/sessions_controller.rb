class SessionsController < ApplicationController
  skip_before_action :require_login, only: [:new, :create, :line_login, :line_callback]

  def new
    @users = User.organizer.order(:id)
  end

  def create
    result = ::Sessions::CreateService.new(params: params).call

    if result.success?
      session[:user_id] = result.user.id
      result.user.increment!(:login_count) if result.user.respond_to?(:login_count)
      return_to = session.delete(:return_to)
      redirect_to(return_to.presence || root_path, notice: I18n.t("sessions.flash.login_success"))
    else
      flash.now[:alert] = I18n.t("sessions.flash.login_failed")
      @users = User.organizer.order(:id)
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to root_path, notice: I18n.t("sessions.flash.logout_success")
  end

  def line_login
    redirect_to "/auth/line"
  end

  def line_callback
    auth = request.env["omniauth.auth"]
    user = User.from_line_omniauth(auth)

    if user
      session[:user_id] = user.id
      user.increment!(:login_count) if user.respond_to?(:login_count)
      return_to = session.delete(:return_to)
      redirect_to(return_to.presence || root_path, notice: I18n.t("sessions.flash.login_success"))
    else
      redirect_to login_path, alert: I18n.t("sessions.flash.login_failed")
    end
  end
end
