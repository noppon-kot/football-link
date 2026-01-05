module Tournaments
  class CreateService
    attr_reader :tournament

    def initialize(params)
      @tournament = Tournament.new(params)
    end

    def call
      assign_defaults
      sync_primary_division_defaults
      tournament.save
    end

    private

    def assign_defaults
      tournament.organizer ||= User.organizer.first || User.first
      tournament.field     ||= Field.first
    end

    def sync_primary_division_defaults
      primary = tournament.tournament_divisions.reject(&:marked_for_destruction?).first
      return unless primary

      tournament.age_category ||= primary.name
      tournament.entry_fee    ||= primary.entry_fee
      tournament.prize_amount ||= primary.prize_amount
    end
  end
end
