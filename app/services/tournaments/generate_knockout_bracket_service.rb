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
        total_teams = @division.team_registrations.confirmed_for_competition.distinct.count(:team_id)
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
      @division.matches.knockout.destroy_all

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
      return unless [4, 8, 16].include?(@bracket_size)

      groups = @division.groups.order(:name).to_a
      return if groups.empty?

      # โหมด knockout_only ต้องใช้ pattern A1-A4/B1-B4 ไม่ใช่ pattern 1A/2B จากรอบแบ่งกลุ่ม
      if @knockout_only && @bracket_size == 8
        assign_first_round_labels_for_knockout_only_8_team!
      elsif groups.size == 2
        assign_first_round_labels_from_groups(groups)
      else
        # ใช้ generic algorithm สำหรับ 3+ สาย
        assign_first_round_labels_generic(groups)
      end
    end

    # Generic algorithm สำหรับ N สาย เข้ารอบ M ทีม
    # หลักการ:
    # 1. สายครบคู่ (4, 8 สาย): ใช้ cross-bracket pairing (A vs C, B vs D หรือ A vs E, B vs F, ...)
    # 2. สายไม่ครบคู่ (3, 5, 6, 7 สาย): ใช้ BP system
    def assign_first_round_labels_generic(groups)
      first_round_matches = @division.matches.knockout.where(round_number: 1).order(:position, :id).to_a
      return if first_round_matches.empty?

      num_groups = groups.size
      ordered_groups = groups.sort_by(&:name)
      group_names = ordered_groups.map { |g| g.name.presence || ('A'.ord + ordered_groups.index(g)).chr }

      # กรณีสายครบคู่ (4, 8 สาย) ใช้ cross-bracket pairing
      if num_groups == 4
        assign_first_round_labels_4_groups(first_round_matches, group_names)
        return
      elsif num_groups == 8
        assign_first_round_labels_8_groups(first_round_matches, group_names)
        return
      end

      # กรณีสายไม่ครบคู่ ใช้ algorithm เดิม (BP system)
      assign_first_round_labels_odd_groups(first_round_matches, group_names, num_groups)
    end

    # 4 สาย: A vs C, B vs D (แชมป์กลุ่มเจอกัน, รองแชมป์เจอกัน)
    # Pattern: สายที่ห่างกัน 2 เจอกัน
    def assign_first_round_labels_4_groups(first_round_matches, group_names)
      # group_names = ["A", "B", "C", "D"]
      a, b, c, d = group_names[0], group_names[1], group_names[2], group_names[3]
      
      slot_pairs = case @bracket_size
      when 4
        # 4 ทีม: แชมป์กลุ่มเท่านั้น
        # 1A vs 1C, 1B vs 1D
        [
          ["1#{a}", "1#{c}"],
          ["1#{b}", "1#{d}"]
        ]
      when 8
        # 8 ทีม: แชมป์ + รองแชมป์
        # 1A vs 2C, 1C vs 2A, 1B vs 2D, 1D vs 2B
        [
          ["1#{a}", "2#{c}"],
          ["1#{c}", "2#{a}"],
          ["1#{b}", "2#{d}"],
          ["1#{d}", "2#{b}"]
        ]
      when 16
        # 16 ทีม: อันดับ 1-4 จากทุกสาย
        # จับคู่ให้ทีมจากสายเดียวกันไม่เจอกันในรอบแรก
        [
          ["1#{a}", "4#{c}"],
          ["2#{c}", "3#{a}"],
          ["1#{c}", "4#{a}"],
          ["2#{a}", "3#{c}"],
          ["1#{b}", "4#{d}"],
          ["2#{d}", "3#{b}"],
          ["1#{d}", "4#{b}"],
          ["2#{b}", "3#{d}"]
        ]
      else
        []
      end

      first_round_matches.each_with_index do |match, idx|
        next if idx >= slot_pairs.size
        home_label, away_label = slot_pairs[idx]
        match.update!(home_slot_label: home_label, away_slot_label: away_label)
      end
    end

    # 8 สาย: A vs E, B vs F, C vs G, D vs H (สายที่ห่างกัน 4 เจอกัน)
    def assign_first_round_labels_8_groups(first_round_matches, group_names)
      # group_names = ["A", "B", "C", "D", "E", "F", "G", "H"]
      a, b, c, d, e, f, g, h = group_names[0..7]
      
      slot_pairs = case @bracket_size
      when 8
        # 8 ทีม: แชมป์กลุ่มเท่านั้น
        # 1A vs 1E, 1B vs 1F, 1C vs 1G, 1D vs 1H
        [
          ["1#{a}", "1#{e}"],
          ["1#{b}", "1#{f}"],
          ["1#{c}", "1#{g}"],
          ["1#{d}", "1#{h}"]
        ]
      when 16
        # 16 ทีม: แชมป์ + รองแชมป์
        # 1A vs 2E, 1E vs 2A, 1B vs 2F, 1F vs 2B, 1C vs 2G, 1G vs 2C, 1D vs 2H, 1H vs 2D
        [
          ["1#{a}", "2#{e}"],
          ["1#{e}", "2#{a}"],
          ["1#{b}", "2#{f}"],
          ["1#{f}", "2#{b}"],
          ["1#{c}", "2#{g}"],
          ["1#{g}", "2#{c}"],
          ["1#{d}", "2#{h}"],
          ["1#{h}", "2#{d}"]
        ]
      when 32
        # 32 ทีม: อันดับ 1-4 จากทุกสาย
        pairs = []
        # A/E bracket
        pairs << ["1#{a}", "4#{e}"]
        pairs << ["2#{e}", "3#{a}"]
        pairs << ["1#{e}", "4#{a}"]
        pairs << ["2#{a}", "3#{e}"]
        # B/F bracket
        pairs << ["1#{b}", "4#{f}"]
        pairs << ["2#{f}", "3#{b}"]
        pairs << ["1#{f}", "4#{b}"]
        pairs << ["2#{b}", "3#{f}"]
        # C/G bracket
        pairs << ["1#{c}", "4#{g}"]
        pairs << ["2#{g}", "3#{c}"]
        pairs << ["1#{g}", "4#{c}"]
        pairs << ["2#{c}", "3#{g}"]
        # D/H bracket
        pairs << ["1#{d}", "4#{h}"]
        pairs << ["2#{h}", "3#{d}"]
        pairs << ["1#{h}", "4#{d}"]
        pairs << ["2#{d}", "3#{h}"]
        pairs
      else
        []
      end

      first_round_matches.each_with_index do |match, idx|
        next if idx >= slot_pairs.size
        home_label, away_label = slot_pairs[idx]
        match.update!(home_slot_label: home_label, away_slot_label: away_label)
      end
    end

    # สายไม่ครบคู่ (3, 5, 6, 7 สาย): ใช้ ranking system
    def assign_first_round_labels_odd_groups(first_round_matches, group_names, num_groups)
      # กรณี 3 สาย 4 ทีม: ใช้ ranking labels
      if num_groups == 3 && @bracket_size == 4
        assign_first_round_labels_3_groups_4_teams(first_round_matches, group_names)
        return
      end

      # กรณี 3 สาย 8 ทีม: ใช้ ranking labels
      if num_groups == 3 && @bracket_size == 8
        assign_first_round_labels_3_groups_8_teams(first_round_matches, group_names)
        return
      end

      # กรณีอื่นๆ ใช้ BP system
      teams_needed = @bracket_size
      
      qualifiers = []
      
      if teams_needed <= num_groups
        num_groups.times do |i|
          qualifiers << { rank: 1, group_idx: i, label: "1#{group_names[i]}" }
        end
      else
        full_rounds = teams_needed / num_groups
        remainder = teams_needed % num_groups
        
        (1..full_rounds).each do |rank|
          num_groups.times do |i|
            qualifiers << { rank: rank, group_idx: i, label: "#{rank}#{group_names[i]}" }
          end
        end
        
        if remainder > 0
          remainder.times do |bp_idx|
            qualifiers << { rank: full_rounds + 1, group_idx: nil, label: "BP#{bp_idx + 1}" }
          end
        end
      end
      
      slot_pairs = generate_cross_group_pairings(qualifiers, num_groups)
      
      first_round_matches.each_with_index do |match, idx|
        next if idx >= slot_pairs.size
        home_label, away_label = slot_pairs[idx]
        match.update!(home_slot_label: home_label, away_slot_label: away_label)
      end
    end

    # 3 สาย 4 ทีม: จัดอันดับตามผลงาน
    # SF1: อันดับ 1 (ดีที่สุด) vs อันดับ 4 (รองแชมป์ที่ดีที่สุด)
    # SF2: อันดับ 2 vs อันดับ 3
    def assign_first_round_labels_3_groups_4_teams(first_round_matches, group_names)
      return unless first_round_matches.size == 2

      # ใช้ label ภาษาไทย: ที่1#1 = อันดับ 1 ที่ดีที่สุดอันดับ 1, ที่1#2 = อันดับ 1 ที่ดีที่สุดอันดับ 2, ที่2#1 = รองแชมป์ที่ดีที่สุด
      slot_pairs = [
        ["ที่1#1", "ที่2#1"],  # อันดับ 1 ที่ดีที่สุด vs รองแชมป์ที่ดีที่สุด
        ["ที่1#2", "ที่1#3"]   # อันดับ 1 ที่ดีอันดับ 2 vs อันดับ 1 ที่ดีอันดับ 3
      ]

      first_round_matches.each_with_index do |match, idx|
        home_label, away_label = slot_pairs[idx]
        match.update!(home_slot_label: home_label, away_slot_label: away_label)
      end
    end

    # 3 สาย 8 ทีม: จัดอันดับตามผลงาน
    # QF1-4: อันดับ 1-8 ตามผลงาน
    # (อาจสลับคู่ถ้าทีมจากสายเดียวกันเจอกัน)
    def assign_first_round_labels_3_groups_8_teams(first_round_matches, group_names)
      return unless first_round_matches.size == 4

      # ใช้ label ภาษาไทย: ที่1#1 = อันดับ 1 ที่ดีที่สุด, ที่2#2 = อันดับ 2 ที่ดีอันดับ 2
      slot_pairs = [
        ["ที่1#1", "ที่3#2"],  # อันดับ 1 ที่ดีที่สุด vs อันดับ 3 ที่ดีอันดับ 2
        ["ที่1#2", "ที่3#1"],  # อันดับ 1 ที่ดีอันดับ 2 vs อันดับ 3 ที่ดีที่สุด
        ["ที่1#3", "ที่2#2"],  # อันดับ 1 ที่ดีอันดับ 3 vs อันดับ 2 ที่ดีอันดับ 2
        ["ที่2#1", "ที่2#3"]   # อันดับ 2 ที่ดีที่สุด vs อันดับ 2 ที่ดีอันดับ 3
      ]

      first_round_matches.each_with_index do |match, idx|
        home_label, away_label = slot_pairs[idx]
        match.update!(home_slot_label: home_label, away_slot_label: away_label)
      end
    end

    # สร้างคู่แข่งขันให้ทีมจากสายเดียวกันไม่เจอกันในรอบแรก (สำหรับสายไม่ครบคู่)
    def generate_cross_group_pairings(qualifiers, num_groups)
      pairs = []
      used = Set.new
      remaining = qualifiers.dup
      
      bp_qualifiers = remaining.select { |q| q[:group_idx].nil? }
      group_qualifiers = remaining.reject { |q| q[:group_idx].nil? }
      
      bp_qualifiers.reverse.each do |bp|
        partner = group_qualifiers.find { |gq| !used.include?(gq[:label]) }
        next unless partner
        
        pairs << [partner[:label], bp[:label]]
        used.add(partner[:label])
        used.add(bp[:label])
      end
      
      unused_group_qualifiers = group_qualifiers.reject { |q| used.include?(q[:label]) }
      
      while unused_group_qualifiers.size >= 2
        hq = unused_group_qualifiers.shift
        next if used.include?(hq[:label])
        
        opponent_idx = unused_group_qualifiers.find_index do |lq|
          !used.include?(lq[:label]) && lq[:group_idx] != hq[:group_idx]
        end
        
        opponent_idx ||= unused_group_qualifiers.find_index { |lq| !used.include?(lq[:label]) }
        
        next unless opponent_idx
        
        opponent = unused_group_qualifiers.delete_at(opponent_idx)
        
        pairs << [hq[:label], opponent[:label]]
        used.add(hq[:label])
        used.add(opponent[:label])
      end
      
      pairs
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
