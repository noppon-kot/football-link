class AdminMessageCommentsController < ApplicationController
  before_action :require_login
  before_action :set_admin_message

  def create
    @comment = @admin_message.admin_message_comments.build(comment_params)
    @comment.user = current_user

    if @comment.save
      redirect_to admin_message_path(@admin_message), notice: "ส่งข้อความเรียบร้อยแล้ว"
    else
      @admin_message_comments = @admin_message.admin_message_comments.includes(:user).order(:created_at)
      flash.now[:alert] = "ไม่สามารถส่งข้อความได้ กรุณาลองใหม่อีกครั้ง"
      render "admin_messages/show", status: :unprocessable_entity
    end
  end

  private

  def set_admin_message
    @admin_message = AdminMessage.find(params[:admin_message_id])
  end

  def comment_params
    params.require(:admin_message_comment).permit(:body)
  end
end
