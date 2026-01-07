module Sessions
  class CreateService
    Result = Struct.new(:success?, :user, :errors, keyword_init: true)

    def initialize(params:)
      @params = params
    end

    def call
      user = User.find_by(id: @params.dig(:session, :user_id))
      return failure([I18n.t("sessions.flash.login_failed")]) unless user

      if organizer_with_wrong_password?(user)
        return failure([I18n.t("sessions.flash.login_failed")])
      end

      Result.new(success?: true, user: user, errors: [])
    end

    private

    def organizer_with_wrong_password?(user)
      user.respond_to?(:organizer?) &&
        user.organizer? &&
        @params.dig(:session, :password) != "1234"
    end

    def failure(errors)
      Result.new(success?: false, user: nil, errors: errors)
    end
  end
end
