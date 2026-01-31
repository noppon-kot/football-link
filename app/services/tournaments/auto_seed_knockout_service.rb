module Tournaments
  class AutoSeedKnockoutService
    Result = Struct.new(:success?, :message, keyword_init: true)

    def initialize(division:, bracket_size:)
      @division = division
      @bracket_size = bracket_size.to_i
    end

    VALID_BRACKET_SIZES = [2, 4, 8, 16, 32, 64].freeze

    def call
      return Result.new(success?: true, message: nil) unless VALID_BRACKET_SIZES.include?(@bracket_size)

      groups = @division.groups.order(:name).to_a
      standings_by_group = compute_standings(groups)

      case
      when groups.size == 2 && @bracket_size == 8
        seed_for_8_teams(groups, standings_by_group)
      when groups.size == 2 && @bracket_size == 4
        seed_for_4_teams(groups, standings_by_group)
      when groups.size == 3 && @bracket_size == 4
        seed_for_4_teams_from_three_groups(groups, standings_by_group)
      when groups.size == 3 && @bracket_size == 8
        seed_for_8_teams_from_three_groups(groups, standings_by_group)
      when groups.size >= 2
        # กรณีอื่นๆ (16/32/64 ทีม หรือมากกว่า 3 สาย)
        # ใช้ generic seeding: เอาอันดับ 1,2,3... จากแต่ละสายมาจับคู่ข้ามสาย
        seed_generic(groups, standings_by_group)
      else
        # ไม่มีสาย หรือมีแค่ 1 สาย → ปล่อยให้ผู้จัดเลือกเองผ่าน dropdown
        return Result.new(success?: true, message: nil)
      end

      Result.new(success?: true, message: nil)
    rescue StandardError => e
      Result.new(success?: false, message: e.message)
    end

    private

    def compute_standings(groups)
      matches = @division.matches.group_stage.where(group_id: groups.map(&:id))
      win_pts  = @division.respond_to?(:points_win)  ? @division.points_win  : 3
      draw_pts = @division.respond_to?(:points_draw) ? @division.points_draw : 1
      loss_pts = @division.respond_to?(:points_loss) ? @division.points_loss : 0
      draw_mode = @division.respond_to?(:draw_mode) ? (@division.draw_mode.presence || "normal") : "normal"
      pk_win_pts  = @division.respond_to?(:points_pk_win)  && @division.points_pk_win.present?  ? @division.points_pk_win  : draw_pts
      pk_loss_pts = @division.respond_to?(:points_pk_loss) && @division.points_pk_loss.present? ? @division.points_pk_loss : draw_pts

      standings_by_group = {}

      groups.each do |group|
        group_matches = matches.where(group_id: group.id)
        team_ids = (group_matches.pluck(:home_team_id) + group_matches.pluck(:away_team_id)).compact.uniq
        stats = {}
        team_ids.each do |tid|
          stats[tid] = { played: 0, won: 0, draw: 0, lost: 0, gf: 0, ga: 0, pts: 0 }
        end

        group_matches.each do |match|
          next if match.home_team_id.blank? || match.away_team_id.blank?
          next unless match.home_score.present? && match.away_score.present?

          h_id = match.home_team_id
          a_id = match.away_team_id
          hs  = match.home_score.to_i
          as  = match.away_score.to_i

          stats[h_id][:played] += 1
          stats[a_id][:played] += 1
          stats[h_id][:gf] += hs; stats[h_id][:ga] += as
          stats[a_id][:gf] += as; stats[a_id][:ga] += hs

          if hs > as
            stats[h_id][:won]  += 1; stats[h_id][:pts] += win_pts
            stats[a_id][:lost] += 1; stats[a_id][:pts] += loss_pts
          elsif hs < as
            stats[a_id][:won]  += 1; stats[a_id][:pts] += win_pts
            stats[h_id][:lost] += 1; stats[h_id][:pts] += loss_pts
          else
            if draw_mode == "pk" && match.decided_by_penalty && match.penalty_winner_side.present?
              winner_id, loser_id = match.penalty_winner_side == "home" ? [h_id, a_id] : [a_id, h_id]
              stats[winner_id][:draw] += 1; stats[winner_id][:pts] += pk_win_pts
              stats[loser_id][:draw]  += 1; stats[loser_id][:pts]  += pk_loss_pts
            else
              stats[h_id][:draw] += 1; stats[h_id][:pts] += draw_pts
              stats[a_id][:draw] += 1; stats[a_id][:pts] += draw_pts
            end
          end
        end

        sorted = stats.map { |tid, s| 
          # Get tiebreaker_rank from team_registration
          team_reg = TeamRegistration.find_by(
            tournament_id: @division.tournament_id,
            tournament_division_id: @division.id,
            group_id: group.id,
            team_id: tid
          )
          tiebreaker = team_reg&.tiebreaker_rank || 999
          [tid, s.merge(tiebreaker_rank: tiebreaker)]
        }.sort_by { |tid, s| [-s[:pts], s[:tiebreaker_rank], -(s[:gf] - s[:ga]), -s[:gf], Team.find(tid).name] }
        standings_by_group[group.id] = sorted
      end

      standings_by_group
    end

    # 3 กลุ่ม เข้ารอบ 4 ทีม: จัดทีมตาม slot label R1#x, R2#x
    # R1#1 = อันดับ 1 ที่ดีที่สุด, R1#2 = อันดับ 1 ที่ดีที่ 2
    # R1#3 = อันดับ 1 ที่ดีที่ 3, R2#1 = อันดับ 2 ที่ดีที่สุด
    # SF1: R1#1 vs R2#1, SF2: R1#2 vs R1#3
    def seed_for_4_teams_from_three_groups(groups, standings_by_group)
      return if groups.any? { |g| standings_by_group[g.id].blank? }

      ordered_groups = groups.sort_by(&:name)

      # รวบรวมแชมป์กลุ่มทั้ง 3 สาย พร้อมสถิติ
      champions = []
      ordered_groups.each do |g|
        standings = standings_by_group[g.id]
        next if standings.blank?
        team_id, stats = standings[0]
        champions << { team_id: team_id, stats: stats, group: g.name }
      end

      # เรียงแชมป์ตามผลงาน (แต้ม > ผลต่างประตู > ประตูได้)
      champions.sort_by! do |q|
        s = q[:stats]
        gd = s[:gf] - s[:ga]
        [-s[:pts], -gd, -s[:gf]]
      end

      # รองแชมป์ที่ดีที่สุด (R2#1)
      runner_up_candidates = []
      ordered_groups.each do |g|
        standings = standings_by_group[g.id]
        next if standings.size < 2
        team_id, stats = standings[1]
        runner_up_candidates << { team_id: team_id, stats: stats, group: g.name }
      end

      runner_up_candidates.sort_by! do |q|
        s = q[:stats]
        gd = s[:gf] - s[:ga]
        [-s[:pts], -gd, -s[:gf]]
      end

      # สร้าง mapping: รองรับทั้ง format เก่าและใหม่
      slot_to_team = {}
      
      # Format ใหม่: R1#1, R1#2, R1#3, R2#1
      slot_to_team["R1#1"] = champions[0][:team_id] if champions[0]
      slot_to_team["R1#2"] = champions[1][:team_id] if champions[1]
      slot_to_team["R1#3"] = champions[2][:team_id] if champions[2]
      slot_to_team["R2#1"] = runner_up_candidates[0][:team_id] if runner_up_candidates[0]
      
      # Format เก่า: R1, R2, R3, R4 (เรียงตามผลงานรวม)
      slot_to_team["R1"] = champions[0][:team_id] if champions[0]
      slot_to_team["R2"] = champions[1][:team_id] if champions[1]
      slot_to_team["R3"] = champions[2][:team_id] if champions[2]
      slot_to_team["R4"] = runner_up_candidates[0][:team_id] if runner_up_candidates[0]

      # อัพเดททีมตาม slot label ในแมตช์
      sf_matches = @division.matches.knockout.where(round_number: 1).order(:position, :id).to_a
      return unless sf_matches.size == 2

      sf_matches.each do |match|
        attrs = {}
        if match.home_slot_label.present? && slot_to_team[match.home_slot_label]
          attrs[:home_team_id] = slot_to_team[match.home_slot_label]
        end
        if match.away_slot_label.present? && slot_to_team[match.away_slot_label]
          attrs[:away_team_id] = slot_to_team[match.away_slot_label]
        end
        match.update!(attrs) if attrs.any?
      end
    end

    # 3 กลุ่ม เข้ารอบ 8 ทีม: จัดทีมตาม slot label R1#x, R2#x, R3#x
    # R1#1-R1#3 = อันดับ 1 เรียงตามผลงาน
    # R2#1-R2#3 = อันดับ 2 เรียงตามผลงาน
    # R3#1-R3#2 = อันดับ 3 ที่ดีที่สุด
    def seed_for_8_teams_from_three_groups(groups, standings_by_group)
      return if groups.any? { |g| standings_by_group[g.id].blank? }

      ordered_groups = groups.sort_by(&:name)

      # รวบรวมทีมแต่ละอันดับ
      rank1_teams = [] # แชมป์สาย
      rank2_teams = [] # รองแชมป์สาย
      rank3_teams = [] # อันดับ 3

      ordered_groups.each do |g|
        standings = standings_by_group[g.id]
        next if standings.blank?
        
        if standings.size >= 1
          team_id, stats = standings[0]
          rank1_teams << { team_id: team_id, stats: stats, group: g.name }
        end
        
        if standings.size >= 2
          team_id, stats = standings[1]
          rank2_teams << { team_id: team_id, stats: stats, group: g.name }
        end

        if standings.size >= 3
          team_id, stats = standings[2]
          rank3_teams << { team_id: team_id, stats: stats, group: g.name }
        end
      end

      # เรียงแต่ละอันดับตามผลงาน
      sort_by_performance = ->(teams) {
        teams.sort_by! do |q|
          s = q[:stats]
          gd = s[:gf] - s[:ga]
          [-s[:pts], -gd, -s[:gf]]
        end
      }

      sort_by_performance.call(rank1_teams)
      sort_by_performance.call(rank2_teams)
      sort_by_performance.call(rank3_teams)

      # สร้าง mapping: รองรับทั้ง format เก่าและใหม่
      slot_to_team = {}
      
      # Format ใหม่: R1#x, R2#x, R3#x
      rank1_teams.each_with_index { |t, i| slot_to_team["R1##{i + 1}"] = t[:team_id] }
      rank2_teams.each_with_index { |t, i| slot_to_team["R2##{i + 1}"] = t[:team_id] }
      rank3_teams.each_with_index { |t, i| slot_to_team["R3##{i + 1}"] = t[:team_id] }
      
      # Format เก่า: R1-R8 (เรียงตามผลงานรวม)
      all_teams = rank1_teams + rank2_teams + rank3_teams.first(2)
      all_teams.each_with_index { |t, i| slot_to_team["R#{i + 1}"] = t[:team_id] }
      
      # Format เก่า: 1A, 2A, 1B, 2B, 1C, 2C, BP1, BP2
      group_names = ordered_groups.map { |g| g.name.presence || ('A'.ord + ordered_groups.index(g)).chr }
      ordered_groups.each_with_index do |g, idx|
        standings = standings_by_group[g.id]
        slot_to_team["1#{group_names[idx]}"] = standings[0][0] if standings.size >= 1
        slot_to_team["2#{group_names[idx]}"] = standings[1][0] if standings.size >= 2
      end
      rank3_teams.first(2).each_with_index { |t, i| slot_to_team["BP#{i + 1}"] = t[:team_id] }

      # อัพเดททีมตาม slot label ในแมตช์
      qf_matches = @division.matches.knockout.where(round_number: 1).order(:position, :id).to_a
      return unless qf_matches.size == 4

      qf_matches.each do |match|
        attrs = {}
        if match.home_slot_label.present? && slot_to_team[match.home_slot_label]
          attrs[:home_team_id] = slot_to_team[match.home_slot_label]
        end
        if match.away_slot_label.present? && slot_to_team[match.away_slot_label]
          attrs[:away_team_id] = slot_to_team[match.away_slot_label]
        end
        match.update!(attrs) if attrs.any?
      end
    end

    # จับคู่ 8 ทีมโดยไม่ให้ทีมจากสายเดียวกันเจอกัน
    # Input: ranked_qualifiers (sorted by performance, best first)
    # Output: array of [home_team_id, away_team_id] pairs
    def pair_without_same_group(ranked)
      # Default pairing: R1 vs R8, R2 vs R7, R3 vs R6, R4 vs R5
      default_pairs = [
        [ranked[0], ranked[7]],
        [ranked[1], ranked[6]],
        [ranked[2], ranked[5]],
        [ranked[3], ranked[4]]
      ]

      # ตรวจสอบว่ามีคู่ไหนที่มาจากสายเดียวกัน
      conflicts = []
      default_pairs.each_with_index do |pair, idx|
        if pair[0][:group] == pair[1][:group]
          conflicts << idx
        end
      end

      # ถ้าไม่มี conflict ใช้ default
      if conflicts.empty?
        return default_pairs.map { |p| [p[0][:team_id], p[1][:team_id]] }
      end

      # มี conflict: ลองสลับคู่เพื่อแก้ปัญหา
      # ใช้ greedy approach: สลับ opponent ระหว่างคู่ที่ conflict
      result_pairs = default_pairs.dup

      conflicts.each do |conflict_idx|
        # หาคู่อื่นที่สามารถสลับได้
        (0...4).each do |other_idx|
          next if other_idx == conflict_idx
          
          # ลองสลับ opponent
          pair_a = result_pairs[conflict_idx]
          pair_b = result_pairs[other_idx]
          
          # สลับ: A1 vs B2, B1 vs A2
          new_pair_a = [pair_a[0], pair_b[1]]
          new_pair_b = [pair_b[0], pair_a[1]]
          
          # ตรวจว่าสลับแล้วไม่ conflict
          if new_pair_a[0][:group] != new_pair_a[1][:group] && 
             new_pair_b[0][:group] != new_pair_b[1][:group]
            result_pairs[conflict_idx] = new_pair_a
            result_pairs[other_idx] = new_pair_b
            break
          end
        end
      end

      result_pairs.map { |p| [p[0][:team_id], p[1][:team_id]] }
    end

    # Generic seeding สำหรับทุกขนาด bracket และจำนวนสาย
    # รองรับทั้ง format เก่า (R1, R2, R3, R4) และ format ใหม่ (R1#1, R1#2, R2#1)
    # หลักการ: จัดทีมตาม slot label ในแมตช์
    def seed_generic(groups, standings_by_group)
      return if groups.empty?

      ordered_groups = groups.sort_by(&:name)
      num_groups = ordered_groups.size
      teams_needed = @bracket_size

      # รวบรวมทีมแต่ละอันดับ พร้อมเรียงตามผลงาน
      teams_by_rank = {} # { rank => [{ team_id:, stats:, group: }, ...] }

      ordered_groups.each do |g|
        standings = standings_by_group[g.id] || []
        standings.each_with_index do |(team_id, stats), rank_idx|
          rank = rank_idx + 1 # 1-indexed
          teams_by_rank[rank] ||= []
          teams_by_rank[rank] << { team_id: team_id, stats: stats, group: g.name }
        end
      end

      # เรียงแต่ละอันดับตามผลงาน
      teams_by_rank.each do |_rank, teams|
        teams.sort_by! do |t|
          s = t[:stats]
          gd = s[:gf] - s[:ga]
          [-s[:pts], -gd, -s[:gf]]
        end
      end

      # สร้าง mapping: รองรับทุก format
      slot_to_team = {}
      
      # Format ใหม่: R1#1, R1#2, R2#1, ...
      teams_by_rank.each do |rank, teams|
        teams.each_with_index do |t, order|
          slot_to_team["R#{rank}##{order + 1}"] = t[:team_id]
        end
      end

      # Format เก่า: R1, R2, R3, R4, ... (เรียงตามผลงานรวม)
      all_teams_sorted = []
      teams_by_rank.keys.sort.each do |rank|
        all_teams_sorted.concat(teams_by_rank[rank])
      end
      all_teams_sorted.each_with_index do |t, idx|
        slot_to_team["R#{idx + 1}"] = t[:team_id]
      end

      # Format: 1A, 2A, 1B, 2B, 1C, 2C, 1D, 2D, ... (อันดับ + ชื่อสาย)
      ordered_groups.each do |g|
        standings = standings_by_group[g.id] || []
        standings.each_with_index do |(team_id, _stats), rank_idx|
          rank = rank_idx + 1
          slot_to_team["#{rank}#{g.name}"] = team_id
        end
      end

      # อัพเดททีมตาม slot label ในแมตช์
      first_round_matches = @division.matches.knockout.where(round_number: 1).order(:position, :id).to_a
      return if first_round_matches.empty?

      first_round_matches.each do |match|
        attrs = {}
        if match.home_slot_label.present? && slot_to_team[match.home_slot_label]
          attrs[:home_team_id] = slot_to_team[match.home_slot_label]
        end
        if match.away_slot_label.present? && slot_to_team[match.away_slot_label]
          attrs[:away_team_id] = slot_to_team[match.away_slot_label]
        end
        match.update!(attrs) if attrs.any?
      end
    end

    # สร้างคู่แข่งขันให้ทีมจากสายเดียวกันไม่เจอกันในรอบแรก
    # กรณี 3 สาย 4 ทีม: 1A vs BP1, 1B vs 1C
    # กรณี 5 สาย 8 ทีม: 1A vs BP3, 1B vs BP2, 1C vs BP1, 1D vs 1E
    def generate_cross_group_pairs(qualifiers, num_groups)
      pairs = []
      used = Set.new
      
      # หา BP qualifiers (group_idx = nil)
      bp_qualifiers = qualifiers.select { |q| q[:group_idx].nil? }
      group_qualifiers = qualifiers.reject { |q| q[:group_idx].nil? }
      
      # จับคู่แชมป์กลุ่มกับ BP ก่อน (ถ้ามี)
      bp_qualifiers.reverse.each do |bp|
        # หาแชมป์กลุ่มที่ยังไม่ถูกใช้
        partner = group_qualifiers.find { |gq| !used.include?(gq[:label]) }
        next unless partner
        
        pairs << [partner, bp]
        used.add(partner[:label])
        used.add(bp[:label])
      end
      
      # จับคู่แชมป์กลุ่มที่เหลือกันเอง (ข้ามสาย)
      unused_group_qualifiers = group_qualifiers.reject { |q| used.include?(q[:label]) }
      
      while unused_group_qualifiers.size >= 2
        hq = unused_group_qualifiers.shift
        next if used.include?(hq[:label])
        
        # หา opponent ที่คนละสาย
        opponent_idx = unused_group_qualifiers.find_index do |lq|
          !used.include?(lq[:label]) && lq[:group_idx] != hq[:group_idx]
        end
        
        # ถ้าหาไม่เจอคนละสาย ให้หาจากที่เหลือ
        opponent_idx ||= unused_group_qualifiers.find_index { |lq| !used.include?(lq[:label]) }
        
        next unless opponent_idx
        
        opponent = unused_group_qualifiers.delete_at(opponent_idx)
        
        pairs << [hq, opponent]
        used.add(hq[:label])
        used.add(opponent[:label])
      end

      pairs
    end

    def seed_for_8_teams(groups, standings_by_group)
      a_group, b_group = groups
      a_standings = standings_by_group[a_group.id]
      b_standings = standings_by_group[b_group.id]

      if a_standings.size < 4 || b_standings.size < 4
        raise "ต้องมีอย่างน้อย 4 ทีมในแต่ละสายเพื่อจัดรอบ 8 ทีม"
      end

      a_top4 = a_standings.first(4).map(&:first)
      b_top4 = b_standings.first(4).map(&:first)

      qf_matches = @division.matches.knockout.where(round_number: 1).order(:position, :id).to_a
      raise "ไม่พบแมตช์รอบ 8 ทีมที่สร้างไว้" unless qf_matches.size == 4

      # Pattern: A1-B4, A2-B3, B2-A3, B1-A4
      assignments = [
        [a_top4[0], b_top4[3]],
        [a_top4[1], b_top4[2]],
        [b_top4[1], a_top4[2]],
        [b_top4[0], a_top4[3]]
      ]

      qf_matches.each_with_index do |match, idx|
        home_id, away_id = assignments[idx]
        match.update!(home_team_id: home_id, away_team_id: away_id)
      end
    end

    def seed_for_4_teams(groups, standings_by_group)
      a_group, b_group = groups
      a_standings = standings_by_group[a_group.id]
      b_standings = standings_by_group[b_group.id]

      if a_standings.size < 2 || b_standings.size < 2
        raise "ต้องมีอย่างน้อย 2 ทีมในแต่ละสายเพื่อจัดรอบ 4 ทีม"
      end

      a_top2 = a_standings.first(2).map(&:first)
      b_top2 = b_standings.first(2).map(&:first)

      sf_matches = @division.matches.knockout.where(round_number: 1).order(:position, :id).to_a
      raise "ไม่พบแมตช์รอบ 4 ทีมที่สร้างไว้" unless sf_matches.size == 2

      # Pattern: A1-B2, B1-A2
      assignments = [
        [a_top2[0], b_top2[1]],
        [b_top2[0], a_top2[1]]
      ]

      sf_matches.each_with_index do |match, idx|
        home_id, away_id = assignments[idx]
        match.update!(home_team_id: home_id, away_team_id: away_id)
      end
    end
  end
end
