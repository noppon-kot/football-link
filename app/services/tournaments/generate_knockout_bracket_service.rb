module Tournaments
  class GenerateKnockoutBracketService
    Result = Struct.new(:success?, :message, keyword_init: true)

    VALID_SIZES = [4, 8, 16, 32, 64].freeze

    ROUND_LABELS = {
      4  => %w[SF FINAL],
      8  => %w[QF SF FINAL],
      16 => %w[R16 QF SF FINAL],
      32 => %w[R32 R16 QF SF FINAL],
      64 => %w[R64 R32 R16 QF SF FINAL]
    }.freeze

    def initialize(division:, bracket_size:, include_third_place: false, enforce_max_by_team_count: true, knockout_only: false)
      @division = division
      @bracket_size = bracket_size.to_i
      @include_third_place = ActiveModel::Type::Boolean.new.cast(include_third_place)
      @enforce_max_by_team_count = enforce_max_by_team_count
      @knockout_only = knockout_only
    end

    # ใส่ label แมตช์รอบถัด ๆ ไป เช่น "ผู้ชนะรอบ4ทีมคู่1 vs ผู้ชนะรอบ4ทีมคู่2"
    # เพื่อให้เห็นโครง bracket ชัดเจนตั้งแต่ยังไม่รู้ชื่อทีมจริง
    def assign_later_round_placeholder_labels!(labels)
      total_rounds = labels.size
      return if total_rounds <= 1

      (2..total_rounds).each do |round_number|
        matches_in_round = (@bracket_size / 2) / (2 ** (round_number - 1))
        prev_round_team_count = @bracket_size / (2 ** (round_number - 2))

        matches = @division.matches.knockout.where(round_number: round_number).order(:position, :id).to_a
        next if matches.empty?

        matches.each_with_index do |match, idx|
          first_prev_match_index = idx * 2 + 1
          second_prev_match_index = idx * 2 + 2

          home_label = "ผู้ชนะรอบ#{prev_round_team_count}ทีมคู่#{first_prev_match_index}"
          away_label = "ผู้ชนะรอบ#{prev_round_team_count}ทีมคู่#{second_prev_match_index}"

          attrs = {}
          attrs[:home_slot_label] = home_label if match.home_team_id.nil?
          attrs[:away_slot_label] = away_label if match.away_team_id.nil?
          match.update!(attrs) if attrs.any?
        end
      end
    end

    def call
      return Result.new(success?: false, message: "รูปแบบน็อคเอาท์ที่เลือกไม่ถูกต้อง") unless VALID_SIZES.include?(@bracket_size)

      if @enforce_max_by_team_count
        total_teams = @division.team_registrations.distinct.count(:team_id)
        if total_teams < @bracket_size
          return Result.new(success?: false, message: "รุ่นนี้มีทีมทั้งหมด #{total_teams} ทีม เลือกจำนวนทีมในรอบน็อคเอาท์ได้ไม่เกิน #{total_teams} ทีม")
        end
      end

      ActiveRecord::Base.transaction do
        create_matches!
      end

      auto_seed_result = ::Tournaments::AutoSeedKnockoutService.new(division: @division, bracket_size: @bracket_size).call

      if auto_seed_result.success?
        Result.new(success?: true, message: "สร้างรอบน็อคเอาท์จำนวน #{@bracket_size} ทีมเรียบร้อยแล้ว")
      else
        Result.new(success?: true, message: "สร้างรอบน็อคเอาท์จำนวน #{@bracket_size} ทีมเรียบร้อยแล้ว (แต่ไม่สามารถจัดทีมอัตโนมัติได้: #{auto_seed_result.message})")
      end
    rescue StandardError => e
      Result.new(success?: false, message: e.message)
    end

    private

    def create_matches!
      # ลบแมตช์น็อคเอาท์เดิมทั้งหมดของรุ่นนี้ก่อน เพื่อไม่ให้ซ้ำซ้อน
      @division.matches.knockout.delete_all

      labels = ROUND_LABELS[@bracket_size]
      total_rounds = labels.size
      matches_in_first_round = @bracket_size / 2

      position_counter = 1

      (1..total_rounds).each do |round_number|
        round_label = labels[round_number - 1]
        matches_in_round = matches_in_first_round / (2 ** (round_number - 1))

        matches_in_round.times do
          @division.matches.create!(
            stage: :knockout,
            round_number: round_number,
            round_label: round_label,
            group: nil,
            home_slot_label: "",
            away_slot_label: "",
            position: position_counter
          )

          position_counter += 1
        end
      end

      assign_first_round_slot_labels_if_applicable!(labels)
      assign_later_round_placeholder_labels!(labels)

      create_third_place_match!(total_rounds) if @include_third_place
    end

    # สำหรับระบบแบ่งกลุ่มที่มี 2 สาย (เช่น A, B) และมีการเข้ารอบ 4 หรือ 8 ทีม
    # ให้ใส่ label ตำแหน่งเช่น 1A, 2B ล่วงหน้าในรอบแรกของน็อคเอาท์
    # ถ้าเป็นโหมด knockout_only (ไม่มีรอบแบ่งกลุ่ม) และ bracket_size = 8
    # ให้ใช้ slot แบบ A1-A2, A3-A4, B1-B2, B3-B4 แทน
    def assign_first_round_slot_labels_if_applicable!(labels)
      return unless [4, 8].include?(@bracket_size)

      groups = @division.groups.order(:name).to_a
      # โหมด knockout_only ต้องใช้ pattern A1-A4/B1-B4 ไม่ใช่ pattern 1A/2B จากรอบแบ่งกลุ่ม
      if @knockout_only && @bracket_size == 8
        assign_first_round_labels_for_knockout_only_8_team!
      elsif groups.size == 2
        assign_first_round_labels_from_groups(groups)
      end
    end

    def assign_first_round_labels_from_groups(groups)
      first_round_number = 1
      first_round_matches = @division.matches.knockout.where(round_number: first_round_number).order(:position, :id).to_a

      a_group, b_group = groups
      a_name = a_group.name.presence || "A"
      b_name = b_group.name.presence || "B"

      slot_pairs =
        if @bracket_size == 8
          # A1-B4, A2-B3, B2-A3, B1-A4
          [
            ["1#{a_name}", "4#{b_name}"],
            ["2#{a_name}", "3#{b_name}"],
            ["2#{b_name}", "3#{a_name}"],
            ["1#{b_name}", "4#{a_name}"]
          ]
        else
          # รอบ 4 ทีม: A1-B2, B1-A2
          [
            ["1#{a_name}", "2#{b_name}"],
            ["1#{b_name}", "2#{a_name}"]
          ]
        end

      first_round_matches.each_with_index do |match, idx|
        home_label, away_label = slot_pairs[idx]
        match.update!(home_slot_label: home_label, away_slot_label: away_label)
      end
    end

    # knockout_only 8 ทีม: จัด slot เป็น A1-A2, A3-A4, B1-B2, B3-B4
    def assign_first_round_labels_for_knockout_only_8_team!
      first_round_matches = @division.matches.knockout.where(round_number: 1).order(:position, :id).to_a
      return unless first_round_matches.size == 4

      slot_pairs = [
        ["A1", "A2"],
        ["A3", "A4"],
        ["B1", "B2"],
        ["B3", "B4"]
      ]

      first_round_matches.each_with_index do |match, idx|
        home_label, away_label = slot_pairs[idx]
        match.update!(home_slot_label: home_label, away_slot_label: away_label)
      end
    end

    def create_third_place_match!(total_rounds)
      @division.matches.create!(
        stage: :knockout,
        round_number: total_rounds,
        round_label: "3RD",
        group: nil,
        home_slot_label: "",
        away_slot_label: "",
        position: 999
      )
    end
  end
end
