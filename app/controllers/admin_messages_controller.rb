class AdminMessagesController < ApplicationController
  before_action :require_login
  before_action :require_admin, only: [:update]
  before_action :set_admin_message, only: [:show, :update]

  def index
    if admin?
      base_scope = AdminMessage.includes(:user, :tournament)
    else
      base_scope = AdminMessage.where(user_id: current_user.id).includes(:tournament)
    end

    # filter by created_at period
    case params[:created_period]
    when "7_days"
      base_scope = base_scope.where("created_at >= ?", 7.days.ago)
    when "30_days"
      base_scope = base_scope.where("created_at >= ?", 30.days.ago)
    end

    # filter by status
    if params[:status].present? && AdminMessage.statuses.key?(params[:status])
      base_scope = base_scope.where(status: params[:status])
    end

    # search by subject
    if params[:q].present?
      q = "%#{params[:q].strip}%"
      base_scope = base_scope.where("subject ILIKE ?", q)
    end

    @current_page = (params[:page] || 1).to_i
    @current_page = 1 if @current_page < 1
    per_page = 10
    total_count = base_scope.count
    @total_pages = (total_count / per_page.to_f).ceil

    @admin_messages = base_scope.order(created_at: :desc)
                                 .offset((@current_page - 1) * per_page)
                                 .limit(per_page)
  end

  def show
    unless admin? || @admin_message.user_id == current_user.id
      return redirect_to root_path, alert: "คุณไม่มีสิทธิ์เข้าหัวข้อนี้"
    end

    @admin_message_comments = @admin_message.admin_message_comments.includes(:user).order(:created_at)
  end

  def new
    @admin_message = AdminMessage.new
    @admin_message.tournament_id = params[:tournament_id] if params[:tournament_id].present?
  end

  def create
    @admin_message = AdminMessage.new(admin_message_params)
    @admin_message.user = current_user

    if @admin_message.save
      redirect_to admin_message_path(@admin_message), notice: "ส่งข้อความถึงแอดมินเรียบร้อยแล้ว"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    previous_status = @admin_message.status

    if @admin_message.update(admin_message_admin_params)
      # ถ้ามีการเปลี่ยนสถานะ ให้สร้างข้อความระบบใน thread เพื่อให้ผู้ใช้เห็น
      if @admin_message.status != previous_status
        status_text = case @admin_message.status
                      when "new_message" then "ใหม่"
                      when "in_progress" then "กำลังดำเนินการ"
                      else "เสร็จแล้ว"
                      end

        @admin_message.admin_message_comments.create(
          user: current_user,
          body: "แอดมินเปลี่ยนสถานะเป็น: #{status_text}"
        )
      end

      if @admin_message.admin_reply.present? && @admin_message.done?
        @admin_message.update(replied_at: Time.current) unless @admin_message.replied_at.present?
      end
      redirect_to admin_messages_path, notice: "อัปเดตสถานะข้อความเรียบร้อยแล้ว"
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def require_admin
    redirect_to root_path, alert: "คุณไม่มีสิทธิ์เข้าหน้านี้" unless admin?
  end

  def set_admin_message
    @admin_message = AdminMessage.find(params[:id])
  end

  def admin_message_params
    params.require(:admin_message).permit(:subject, :body, :tournament_id, :message_type)
  end

  def admin_message_admin_params
    params.require(:admin_message).permit(:status, :admin_reply)
  end
end
