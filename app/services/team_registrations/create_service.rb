module TeamRegistrations
  class CreateService
    Result = Struct.new(:success?, :tournament, :registration, :errors, keyword_init: true)

    def initialize(tournament:, params:, current_user: nil)
      @tournament = tournament
      @params     = params
      @current_user = current_user
    end

    def call
      divisions = @tournament.tournament_divisions.order(:position, :id)

      division_id = if divisions.size == 1
                      divisions.first.id
                    else
                      @params.dig(:registration, :tournament_division_id)
                    end

      team_params = @params.require(:registration).permit(:team_name, :contact_name, :contact_phone, :line_id, :logo)

      registration = nil

      ActiveRecord::Base.transaction do
        default_manager_user_id = @current_user&.id.presence || @tournament.organizer_id

        team = Team.create!(
          name:          team_params[:team_name],
          contact_name:  team_params[:contact_name],
          contact_phone: team_params[:contact_phone],
          city:          @tournament.city,
          province:      @tournament.province,
          line_id:       team_params[:line_id]
        )

        if team_params[:logo].present?
          team.replace_logo!(team_params[:logo])
        end

        registration = TeamRegistration.create!(
          team:                   team,
          tournament:             @tournament,
          tournament_division_id: division_id.presence,
          manager_user_id:        default_manager_user_id,
          status:                 :interested,
          notes:                  "สมัครผ่านฟอร์มสนใจสมัคร"
        )

        if registration.manager_user_id.present?
          begin
            TeamRegistrationManager.create!(team_registration: registration, user_id: registration.manager_user_id)
          rescue ActiveRecord::RecordNotUnique
            # ignore
          end
        end
      end

      Result.new(success?: true, tournament: @tournament, registration: registration, errors: [])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, tournament: @tournament, registration: nil, errors: Array(e.record&.errors&.full_messages).flatten)
    end
  end
end
