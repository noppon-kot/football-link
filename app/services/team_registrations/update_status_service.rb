module TeamRegistrations
  class UpdateStatusService
    Result = Struct.new(:success?, :registration, :errors, keyword_init: true)

    def initialize(registration:, params:)
      @registration = registration
      @params       = params
    end

    def call
      if @registration.update(permitted_params)
        Result.new(success?: true, registration: @registration, errors: [])
      else
        Result.new(success?: false, registration: @registration, errors: @registration.errors.full_messages)
      end
    end

    private

    def permitted_params
      @params.require(:team_registration).permit(:status)
    end
  end
end
