class TournamentStaffsController < ApplicationController
  before_action :require_login
  before_action :set_tournament
  before_action :require_staff_manage_permission

  def show
    q = params[:q].to_s.strip
    return if q.blank?

    base = User.all

    if q.match?(/\A\d+\z/)
      @candidates = base.where(id: q.to_i)
    else
      @candidates = base
                    .where("line_id = ? OR LOWER(name) LIKE ?", q, "%#{q.downcase}%")
                    .order(:id)
                    .limit(20)
    end
  end

  def update
    if params[:remove_user_id].present?
      target_id = params[:remove_user_id].to_i

      if target_id == @tournament.organizer_id
        return redirect_to tournament_staff_path(@tournament), alert: "ไม่สามารถลบผู้จัดหลักได้"
      end

      @tournament.tournament_staffs.where(user_id: target_id).destroy_all
      return redirect_to tournament_staff_path(@tournament), notice: "ลบผู้จัดร่วมเรียบร้อยแล้ว"
    end

    user_id = params.dig(:staff, :user_id).presence
    query = params.dig(:staff, :query).to_s.strip

    if user_id.blank? && query.blank?
      return redirect_to tournament_staff_path(@tournament), alert: "กรุณาเลือกผู้ใช้ก่อน"
    end

    user = if user_id.present?
             User.find_by(id: user_id)
           elsif query.match?(/\A\d+\z/)
             User.find_by(id: query.to_i)
           else
             User.find_by(line_id: query) || User.where("LOWER(name) LIKE ?", "%#{query.downcase}%").order(:id).first
           end

    unless user
      return redirect_to tournament_staff_path(@tournament), alert: "ไม่พบผู้ใช้ที่ค้นหา"
    end

    if user.id == @tournament.organizer_id
      return redirect_to tournament_staff_path(@tournament), alert: "ผู้ใช้นี้เป็นผู้จัดหลักอยู่แล้ว"
    end

    begin
      @tournament.tournament_staffs.create!(user: user)
    rescue ActiveRecord::RecordNotUnique
      # ignore
    end

    redirect_to tournament_staff_path(@tournament), notice: "เพิ่มผู้จัดร่วมเรียบร้อยแล้ว"
  end

  private

  def set_tournament
    @tournament = Tournament.find(params[:id])
  end

  def require_staff_manage_permission
    return if admin?
    return if @tournament.organizer_id == current_user.id

    redirect_to tournament_path(@tournament), alert: I18n.t("sessions.flash.login_required")
  end
end
