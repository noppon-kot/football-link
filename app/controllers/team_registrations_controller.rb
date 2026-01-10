class TeamRegistrationsController < ApplicationController
  before_action :require_login
  before_action :set_tournament
  before_action :set_registration, only: [:update, :destroy, :edit_team, :update_team]
  before_action :require_manage_permission, only: [:update, :destroy, :edit_team, :update_team]

  def new
    @divisions = @tournament.tournament_divisions.order(:position, :id)
  end

  def edit_team
    @team = @registration.team
  end

  def update_team
    @team = @registration.team
    permitted = params.require(:team).permit(:name, :contact_name, :contact_phone, :line_id, :logo)

    if permitted[:logo].present?
      @team.replace_logo!(permitted[:logo])
    end

    if @team.update(permitted.except(:logo))
      redirect_to teams_tournament_path(@tournament), notice: "บันทึกข้อมูลทีมเรียบร้อยแล้ว"
    else
      flash.now[:alert] = @team.errors.full_messages.to_sentence
      render :edit_team, status: :unprocessable_entity
    end
  end

  def create
    @divisions = @tournament.tournament_divisions.order(:position, :id)

    result = ::TeamRegistrations::CreateService.new(
      tournament: @tournament,
      params: params
    ).call

    if result.success?
      if current_user && params.dig(:registration, :line_id).present?
        current_user.update(line_id: params.dig(:registration, :line_id))
      end
      redirect_to teams_tournament_path(@tournament), notice: I18n.t("team_registrations.flash.create_success")
    else
      flash.now[:alert] = "กรุณากรอกข้อมูลทีมและข้อมูลผู้ติดต่อให้ครบถ้วน"
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if locked_registration?(@registration)
      return redirect_to teams_tournament_path(@tournament), alert: "ไม่สามารถแก้ไขทีมหลังจากมีการแบ่งสายการแข่งขันแล้ว"
    end

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
    if locked_registration?(@registration)
      return redirect_to teams_tournament_path(@tournament), alert: "ไม่สามารถลบทีมหลังจากมีการแบ่งสายการแข่งขันแล้ว"
    end

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
    unless can_manage_registrations?(@tournament)
      redirect_to @tournament, alert: I18n.t("sessions.flash.login_required")
    end
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
