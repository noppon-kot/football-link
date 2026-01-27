class AdminUsersController < ApplicationController
  before_action :require_login
  before_action :require_admin

  def index
    base = User.order(:id)

    if params[:package].present? && User.packages.key?(params[:package])
      base = base.where(package: User.packages[params[:package]])
    end

    if params[:q].present?
      q = params[:q].to_s.strip
      if q.match?(/\A\d+\z/)
        base = base.where(id: q.to_i)
      else
        like = "%#{q.downcase}%"
        base = base.where("LOWER(name) LIKE ? OR LOWER(username) LIKE ? OR line_id = ?", like, like, q)
      end
    end

    @users = base.limit(200)
  end

  def edit
    @user = User.find(params[:id])
  end

  def update
    @user = User.find(params[:id])
    permitted = params.require(:user).permit(:package)

    if @user.update(permitted)
      redirect_to admin_users_path, notice: "บันทึกแพ็กเกจผู้ใช้เรียบร้อยแล้ว"
    else
      flash.now[:alert] = @user.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def require_admin
    redirect_to root_path, alert: "คุณไม่มีสิทธิ์เข้าหน้านี้" unless admin?
  end
end
