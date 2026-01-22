class RegistrationsController < ApplicationController
  skip_before_action :require_login, only: [:new, :create]

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)
    @user.username = @user.username.to_s.strip.downcase

    begin
      if @user.save
        session[:user_id] = @user.id
        redirect_to root_path, notice: "สมัครสมาชิกเรียบร้อยแล้ว"
      else
        flash.now[:alert] = @user.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordNotUnique
      @user.errors.add(:username, "ถูกใช้งานแล้ว")
      flash.now[:alert] = @user.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:user).permit(:name, :username, :password, :password_confirmation, :security_question, :security_answer)
  end
end
