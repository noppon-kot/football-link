module Tournaments
  class GenerateMockScheduleService
    def initialize(division:, group_count:, slots_per_group:, match_format: nil)
      @division = division
      @group_count = group_count.to_i
      @slots_per_group = slots_per_group.to_i
      @match_format = (match_format.presence || safe_division_match_format)
      @group_sizes = []
    end

    def call
      return false if @group_count <= 0 || @slots_per_group <= 0

      ActiveRecord::Base.transaction do
        @division.groups.destroy_all
        @division.matches.destroy_all

        calculate_group_sizes
        groups = build_groups
        build_matches(groups)
      end

      true
    end

    private

    def build_groups
      labels = ("A".."Z").to_a
      @group_count.times.map do |i|
        @division.groups.create!(name: labels[i])
      end
    end

    def build_matches(groups)
      groups.each_with_index do |group, idx|
        group_size = @group_sizes[idx] || @slots_per_group
        next if group_size <= 0

        slot_labels = (1..group_size).map { |n| "#{group.name}#{n}" }
        # all pair combinations within the group
        if @match_format == "home_away"
          slot_labels.combination(2).each do |a, b|
            @division.matches.create!(
              group: group,
              home_slot_label: a,
              away_slot_label: b,
              status: :scheduled
            )
            @division.matches.create!(
              group: group,
              home_slot_label: b,
              away_slot_label: a,
              status: :scheduled
            )
          end
        else
          slot_labels.combination(2).each do |home_label, away_label|
            @division.matches.create!(
              group: group,
              home_slot_label: home_label,
              away_slot_label: away_label,
              status: :scheduled
            )
          end
        end
      end
    end

    def calculate_group_sizes
      total_teams = @division.team_registrations.count

      if total_teams > 0
        base = total_teams / @group_count
        extra = total_teams % @group_count

        @group_sizes = (0...@group_count).map do |i|
          base + (i < extra ? 1 : 0)
        end
      else
        # ถ้าไม่มีทีม ให้ใช้จำนวนทีมต่อสายที่ผู้ใช้กรอกเท่ากันทุกสาย
        @group_sizes = Array.new(@group_count, @slots_per_group)
      end
    end

    def safe_division_match_format
      if @division.respond_to?(:match_format)
        @division.match_format
      else
        "single_leg"
      end
    end
  end
end
