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

        # ใช้การจัดตารางแบบ round-robin เพื่อไม่ให้ทีมในตำแหน่งแรก ๆ เตะติดกันหลายแมตช์
        rounds = round_robin_pairs(slot_labels)

        rounds.each do |pairs|
          pairs.each do |home_label, away_label|
            if @match_format == "home_away"
              @division.matches.create!(
                group: group,
                home_slot_label: home_label,
                away_slot_label: away_label,
                status: :scheduled
              )
              @division.matches.create!(
                group: group,
                home_slot_label: away_label,
                away_slot_label: home_label,
                status: :scheduled
              )
            else
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

    # สร้างคู่แข่งแบบ round-robin จากรายชื่อ slot_labels
    # ตัวอย่าง 4 ทีม: ได้รอบเป็น [[A1,A2],[A3,A4]], [[A1,A3],[A2,A4]], [[A1,A4],[A2,A3]]
    def round_robin_pairs(slot_labels)
      teams = slot_labels.dup

      # ถ้าจำนวนทีมเป็นเลขคี่ ให้ใส่ bye (nil) เพื่อให้หมุนรอบได้ครบ
      if teams.size.odd?
        teams << nil
      end

      n = teams.size
      rounds_count = n - 1
      half = n / 2
      schedule = []

      rounds_count.times do
        pairs = []

        (0...half).each do |i|
          t1 = teams[i]
          t2 = teams[n - 1 - i]

          # ข้ามคู่ที่มี bye
          next if t1.nil? || t2.nil?

          pairs << [t1, t2]
        end

        schedule << pairs

        # หมุนลำดับทีมแบบ circle method: ตำแหน่งแรกอยู่ที่เดิม ตัวอื่นหมุน
        fixed = teams.first
        rotating = teams[1..-1]
        rotating.rotate!(-1)
        teams = [fixed] + rotating
      end

      schedule
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
