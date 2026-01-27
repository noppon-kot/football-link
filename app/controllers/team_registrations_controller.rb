class TeamRegistrationsController < ApplicationController
  before_action :require_login
  before_action :set_tournament
  before_action :set_registration, only: [:update, :destroy, :edit_team, :update_team]
  before_action :require_manage_permission, only: [:update, :destroy, :edit_team, :update_team, :edit_manager, :update_manager]

  def new
    @divisions = @tournament.tournament_divisions.order(:position, :id)
  end

  def edit_team
    @team = @registration.team
    @divisions = @tournament.tournament_divisions.order(:position, :id)
  end

  def update_team
    @team = @registration.team
    @divisions = @tournament.tournament_divisions.order(:position, :id)
    permitted = params.require(:team).permit(:name, :contact_name, :contact_phone, :line_id, :logo)

    submitted_division_id = params.dig(:team_registration, :tournament_division_id).presence

    if submitted_division_id.present? && @divisions.size > 1
      unless locked_registration?(@registration)
        division = @divisions.find_by(id: submitted_division_id)
        if division
          @registration.update(tournament_division_id: division.id)
        end
      end
    end

    if permitted[:logo].present?
      @team.replace_logo!(permitted[:logo])
    end

    if @team.update(permitted)
      if can_manage_registrations?(@tournament)
        redirect_to teams_tournament_path(@tournament), notice: "บันทึกข้อมูลทีมเรียบร้อยแล้ว"
      else
        redirect_to teams_tournament_path(@tournament), notice: "บันทึกข้อมูลทีมเรียบร้อยแล้ว"
      end
    else
      flash.now[:alert] = @team.errors.full_messages.to_sentence
      render :edit_team, status: :unprocessable_entity
    end
  end

  def edit_manager
    @registration = @tournament.team_registrations.find(params[:id])

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

  def update_manager
    @registration = @tournament.team_registrations.find(params[:id])

    if params[:remove_user_id].present?
      @registration.team_registration_managers.where(user_id: params[:remove_user_id]).destroy_all
      if @registration.manager_users.empty?
        @registration.update(manager_user_id: @tournament.organizer_id)
      end
      return redirect_to edit_manager_tournament_team_registration_path(@tournament, @registration), notice: "ลบผู้จัดการทีมเรียบร้อยแล้ว"
    end

    user_id = params.dig(:manager, :user_id).presence
    query = params.dig(:manager, :query).to_s.strip

    if user_id.blank? && query.blank?
      @registration.team_registration_managers.destroy_all
      @registration.update(manager_user_id: @tournament.organizer_id)
      return redirect_to teams_tournament_path(@tournament), notice: "ตั้งค่าเป็นผู้จัดรายการเรียบร้อยแล้ว"
    end

    user = if user_id.present?
             User.find_by(id: user_id)
           elsif query.match?(/\A\d+\z/)
             User.find_by(id: query.to_i)
           else
             User.find_by(line_id: query) || User.where("LOWER(name) LIKE ?", "%#{query.downcase}%").order(:id).first
           end

    unless user
      flash.now[:alert] = "ไม่พบผู้ใช้ที่ค้นหา"
      return render :edit_manager, status: :unprocessable_entity
    end

    begin
      @registration.team_registration_managers.create!(user: user)
    rescue ActiveRecord::RecordNotUnique
      # already added
    end

    if @registration.manager_user_id.blank? || @registration.manager_user_id == @tournament.organizer_id
      @registration.update(manager_user_id: user.id)
    end

    redirect_to edit_manager_tournament_team_registration_path(@tournament, @registration), notice: "เพิ่มผู้จัดการทีมเรียบร้อยแล้ว"
  end

  def create
    @divisions = @tournament.tournament_divisions.order(:position, :id)

    result = ::TeamRegistrations::CreateService.new(
      tournament: @tournament,
      params: params,
      current_user: current_user
    ).call

    if result.success?
      if current_user && params.dig(:registration, :line_id).present?
        current_user.update(line_id: params.dig(:registration, :line_id))
      end
      redirect_to teams_tournament_path(@tournament), notice: I18n.t("team_registrations.flash.create_success")
    else
      flash.now[:alert] = result.errors.present? ? result.errors.join(", ") : "กรุณาตรวจสอบข้อมูลการสมัครทีม"
      render :new, status: :unprocessable_entity
    end
  end

  def update
    result = ::TeamRegistrations::UpdateStatusService.new(
      registration: @registration,
      params: params
    ).call

    if result.success?
      redirect_to teams_tournament_path(@tournament), notice: I18n.t("team_registrations.flash.update_success", default: "อัปเดตสถานะทีมเรียบร้อยแล้ว")
    else
      redirect_to teams_tournament_path(@tournament), alert: result.errors.join(", ")
    end
  end

  def destroy
    result = ::TeamRegistrations::DestroyService.new(
      registration: @registration
    ).call

    if result.success?
      redirect_to teams_tournament_path(@tournament), notice: I18n.t("team_registrations.flash.destroy_success", default: "ลบทีมออกจากรายการแข่งแล้ว")
    else
      redirect_to teams_tournament_path(@tournament), alert: result.errors.join(", ")
    end
  end

  private

  def set_tournament
    @tournament = Tournament.find(params[:tournament_id])
  end

  def set_registration
    @registration = @tournament.team_registrations.find(params[:id])
  end

  def require_manage_permission
    can_manage_sensitive = admin? || @tournament.organizer_id == current_user.id
    return if can_manage_sensitive

    if %w[edit_team update_team].include?(action_name) && @registration.present?
      return if @registration.team_registration_managers.where(user_id: current_user.id).exists?
      return if @registration.manager_user_id == current_user.id
    end

    redirect_to @tournament, alert: I18n.t("sessions.flash.login_required")
  end

  def team_registration_params
    params.require(:team_registration).permit(:status)
  end

  def locked_registration?(registration)
    division = registration.tournament_division
    return false unless division

    division.groups.exists? || division.matches.exists?
  end
end
