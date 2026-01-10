module Tournaments
  class AutoAdvanceKnockoutWinnersService
    Result = Struct.new(:success?, :message, keyword_init: true)

    def initialize(division:)
      @division = division
    end

    def call
      knockout_matches = @division.matches.knockout.order(:round_number, :position, :id).to_a
      return Result.new(success?: true, message: nil) if knockout_matches.empty?

      grouped = knockout_matches.group_by(&:round_number)
      round_numbers = grouped.keys.sort
      return Result.new(success?: true, message: nil) if round_numbers.size <= 1

      round_numbers.each_cons(2) do |current_round, next_round|
        current_matches = grouped[current_round] || []
        next_round_matches = grouped[next_round] || []
        next if current_matches.empty? || next_round_matches.empty?

        current_matches.each_with_index do |match, idx|
          next unless match.home_score.present? && match.away_score.present?

          winner = determine_winner(match)
          next unless winner

          target_match = next_round_matches[idx / 2]
          next unless target_match

          update_attrs = {}
          if idx.even?
            update_attrs[:home_team_id] = winner.id if target_match.home_team_id != winner.id
          else
            update_attrs[:away_team_id] = winner.id if target_match.away_team_id != winner.id
          end

          target_match.update!(update_attrs) if update_attrs.any?
        end
      end

      Result.new(success?: true, message: nil)
    rescue StandardError => e
      Result.new(success?: false, message: e.message)
    end

    private

    def determine_winner(match)
      hs = match.home_score.to_i
      as = match.away_score.to_i

      return nil if hs == as && !match.decided_by_penalty

      if hs > as
        match.home_team
      elsif as > hs
        match.away_team
      else
        # เสมอแต่มีตัดสินด้วยจุดโทษ
        case match.penalty_winner_side
        when "home" then match.home_team
        when "away" then match.away_team
        else
          nil
        end
      end
    end
  end
end
