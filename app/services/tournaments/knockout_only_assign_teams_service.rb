module Tournaments
  class KnockoutOnlyAssignTeamsService
    Result = Struct.new(:success?, :message, keyword_init: true)

    def initialize(division:, bracket_size:)
      @division = division
      @bracket_size = bracket_size.to_i
    end

    def call
      matches = @division.matches.knockout.order(:round_number, :position, :id).to_a
      return Result.new(success?: false, message: "ไม่พบโปรแกรมรอบน็อคเอาท์สำหรับรุ่นนี้") if matches.empty?

      first_round_matches = matches.select { |m| m.round_number == 1 }
      return Result.new(success?: false, message: "ไม่พบแมตช์รอบแรกของรอบน็อคเอาท์") if first_round_matches.empty?

      total_teams = @division.team_registrations.includes(:team).distinct.order(:id).map(&:team).compact.shuffle
      if total_teams.empty?
        return Result.new(success?: false, message: "ยังไม่มีทีมในรุ่นนี้")
      end

      side_size = @bracket_size / 2

      a_teams = total_teams.first(side_size)
      b_teams = total_teams.drop(side_size).first(side_size)

      # ถ้าทีมไม่พอให้เติม nil เพื่อให้ครบคู่
      a_teams.fill(nil, a_teams.length...side_size)
      b_teams.fill(nil, b_teams.length...side_size)

      a_matches = first_round_matches.first(side_size / 2)
      b_matches = first_round_matches.drop(side_size / 2).first(side_size / 2)

      ActiveRecord::Base.transaction do
        assign_side(a_matches, a_teams, "A")
        assign_side(b_matches, b_teams, "B")
      end

      Result.new(success?: true, message: nil)
    rescue StandardError => e
      Result.new(success?: false, message: e.message)
    end

    private

    def assign_side(matches, teams, side_prefix)
      matches.each_with_index do |match, idx|
        t1 = teams[idx * 2]
        t2 = teams[idx * 2 + 1]

        slot1 = "#{side_prefix}#{idx * 2 + 1}"
        slot2 = "#{side_prefix}#{idx * 2 + 2}"

        attrs = {
          home_slot_label: slot1,
          away_slot_label: slot2
        }

        attrs[:home_team_id] = t1&.id
        attrs[:away_team_id] = t2&.id

        match.update!(attrs)
      end
    end
  end
end
