module TeamRegistrations
  class DestroyService
    Result = Struct.new(:success?, :registration, :errors, keyword_init: true)

    def initialize(registration:)
      @registration = registration
    end

    def call
      @registration.destroy
      Result.new(success?: true, registration: @registration, errors: [])
    rescue StandardError => e
      Result.new(success?: false, registration: @registration, errors: [e.message])
    end
  end
end
