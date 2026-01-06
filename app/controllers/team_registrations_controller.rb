class TeamRegistrationsController < ApplicationController
  before_action :require_login
  before_action :set_tournament
  before_action :set_registration, only: [:update, :destroy]
  before_action :require_manage_permission, only: [:update, :destroy]

  def new
    @divisions = @tournament.tournament_divisions.order(:position, :id)
  end

  def create
    @divisions = @tournament.tournament_divisions.order(:position, :id)

    division_id = if @divisions.size == 1
                    @divisions.first.id
                  else
                    params.dig(:registration, :tournament_division_id)
                  end

    team_params = params.require(:registration).permit(:team_name, :contact_name, :contact_phone, :line_id)

    ActiveRecord::Base.transaction do
      team = Team.create!(
        name:          team_params[:team_name],
        contact_name:  team_params[:contact_name],
        contact_phone: team_params[:contact_phone],
        city:          @tournament.city,
        province:      @tournament.province,
        line_id:       team_params[:line_id]
      )

      TeamRegistration.create!(
        team:                team,
        tournament:          @tournament,
        tournament_division_id: division_id.presence,
        status:              :interested,
        notes:               "สมัครผ่านฟอร์มสนใจสมัคร"
      )
    end

    redirect_to @tournament, notice: I18n.t("team_registrations.flash.create_success")
  rescue ActiveRecord::RecordInvalid
    flash.now[:alert] = "กรุณากรอกข้อมูลทีมและข้อมูลผู้ติดต่อให้ครบถ้วน"
    render :new, status: :unprocessable_entity
  end

  def update
    if @registration.update(team_registration_params)
      redirect_to @tournament, notice: I18n.t("team_registrations.flash.update_success", default: "อัปเดตสถานะทีมเรียบร้อยแล้ว")
    else
      redirect_to @tournament, alert: @registration.errors.full_messages.join(", ")
    end
  end

  def destroy
    @registration.destroy
    redirect_to @tournament, notice: I18n.t("team_registrations.flash.destroy_success", default: "ลบทีมออกจากรายการแข่งแล้ว")
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
end
