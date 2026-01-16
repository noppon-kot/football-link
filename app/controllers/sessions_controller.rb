class SessionsController < ApplicationController
  skip_before_action :require_login, only: [:new, :create, :line_login, :line_callback]

  def new
    @users = if Rails.env.development?
               User.organizer.or(User.where(provider: "dev")).order(:id)
             else
               User.organizer.order(:id)
             end
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
      @users = if Rails.env.development?
                 User.organizer.or(User.where(provider: "dev")).order(:id)
               else
                 User.organizer.order(:id)
               end
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to root_path, notice: I18n.t("sessions.flash.logout_success")
  end

  def impersonate
    return head :not_found unless Rails.env.development?
    return redirect_to root_path unless admin?

    target = User.find_by(id: params[:id])
    return redirect_to root_path, alert: "ไม่พบผู้ใช้" unless target

    session[:impersonator_user_id] ||= current_user.id
    session[:user_id] = target.id
    redirect_to root_path, notice: "สลับเป็นผู้ใช้ #{target.name} แล้ว"
  end

  def stop_impersonating
    return head :not_found unless Rails.env.development?
    return redirect_to root_path unless session[:impersonator_user_id]

    original = User.find_by(id: session.delete(:impersonator_user_id))
    session[:user_id] = original&.id
    redirect_to root_path, notice: "กลับเป็นผู้จัดแล้ว"
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
