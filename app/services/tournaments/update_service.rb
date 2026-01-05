module Tournaments
  class UpdateService
    attr_reader :tournament

    def initialize(tournament, params)
      @tournament = tournament
      @params     = params
    end

    def call
      tournament.assign_attributes(@params)
      sync_primary_division_defaults
      tournament.save
    end

    private

    def sync_primary_division_defaults
      primary = tournament.tournament_divisions.reject(&:marked_for_destruction?).first
      return unless primary

      tournament.age_category ||= primary.name
      tournament.entry_fee    ||= primary.entry_fee
      tournament.prize_amount ||= primary.prize_amount
    end
  end
end
