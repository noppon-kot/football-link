class SessionsController < ApplicationController
  def new
    @users = User.order(:id)
  end

  def create
    user = User.find_by(id: params.dig(:session, :user_id))
    if user
      session[:user_id] = user.id
      return_to = session.delete(:return_to)
      redirect_to(return_to.presence || root_path, notice: I18n.t("sessions.flash.login_success"))
    else
      flash.now[:alert] = I18n.t("sessions.flash.login_failed")
      @users = User.order(:id)
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to root_path, notice: I18n.t("sessions.flash.logout_success")
  end
end
