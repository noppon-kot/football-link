class PasswordResetsController < ApplicationController
  skip_before_action :require_login, only: [:new, :create, :update]

  def new
    @user = nil
  end

  def create
    @username = params[:username].to_s.strip.downcase
    @user = User.find_by(username: @username)

    unless @user
      flash.now[:alert] = "ไม่พบ username นี้"
      return render :new, status: :unprocessable_entity
    end

    render :new
  end

  def update
    @username = params[:username].to_s.strip.downcase
    @user = User.find_by(username: @username)

    unless @user
      flash.now[:alert] = "ไม่พบ username นี้"
      return render :new, status: :unprocessable_entity
    end

    unless @user.security_answer_correct?(params[:security_answer])
      flash.now[:alert] = "คำตอบไม่ถูกต้อง"
      return render :new, status: :unprocessable_entity
    end

    @user.password = params[:password]
    @user.password_confirmation = params[:password_confirmation]

    if @user.save
      redirect_to login_path, notice: "ตั้งรหัสผ่านใหม่เรียบร้อยแล้ว"
    else
      flash.now[:alert] = @user.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end
end
