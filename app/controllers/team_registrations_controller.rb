class TeamRegistrationsController < ApplicationController
  def new
    @tournament = Tournament.includes(:tournament_divisions).find(params[:tournament_id])
    @divisions  = @tournament.tournament_divisions.order(:position, :id)
  end

  def create
    @tournament = Tournament.find(params[:tournament_id])
    @divisions  = @tournament.tournament_divisions.order(:position, :id)

    division_id = if @divisions.size == 1
                    @divisions.first.id
                  else
                    params.dig(:registration, :tournament_division_id)
                  end

    team_params = params.require(:registration).permit(:team_name, :contact_name, :contact_phone)

    ActiveRecord::Base.transaction do
      team = Team.create!(
        name:          team_params[:team_name],
        contact_name:  team_params[:contact_name],
        contact_phone: team_params[:contact_phone],
        city:          @tournament.city,
        province:      @tournament.province
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
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = e.record.errors.full_messages.join(", ")
    render :new, status: :unprocessable_entity
  end
end
