module Tournaments
  class GenerateMockScheduleService
    def initialize(division:, group_count:, slots_per_group:)
      @division = division
      @group_count = group_count.to_i
      @slots_per_group = slots_per_group.to_i
    end

    def call
      return false if @group_count <= 0 || @slots_per_group <= 0

      ActiveRecord::Base.transaction do
        @division.groups.destroy_all
        @division.matches.destroy_all

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
      groups.each do |group|
        slot_labels = (1..@slots_per_group).map { |n| "#{group.name}#{n}" }
        # all pair combinations within the group
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
end
