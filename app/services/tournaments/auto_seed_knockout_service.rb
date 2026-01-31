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

    # 3 กลุ่ม เข้ารอบ 4 ทีม: จัดอันดับตามผลงานที่ดีที่สุด
    # หลักการ:
    # - เอาแชมป์กลุ่มทั้ง 3 + รองแชมป์ที่ดีที่สุด 1 ทีม = 4 ทีม
    # - จัดอันดับ 1-4 ตามผลงาน (แต้ม > ผลต่างประตู > ประตูได้)
    # - จับคู่: อันดับ 1 vs อันดับ 4, อันดับ 2 vs อันดับ 3
    # - **สำคัญ:** ทีมจากสายเดียวกันต้องไม่เจอกันในรอบแรก
    def seed_for_4_teams_from_three_groups(groups, standings_by_group)
      return if groups.any? { |g| standings_by_group[g.id].blank? }

      ordered_groups = groups.sort_by(&:name)

      # รวบรวมแชมป์กลุ่มทั้ง 3 สาย พร้อมสถิติ
      all_qualifiers = []

      ordered_groups.each do |g|
        standings = standings_by_group[g.id]
        next if standings.blank?

        # อันดับ 1 ของสาย
        team_id, stats = standings[0]
        all_qualifiers << { team_id: team_id, stats: stats, rank: 1, group: g.name }
      end

      # เพิ่มรองแชมป์ที่ดีที่สุด 1 ทีม
      runner_up_candidates = []
      ordered_groups.each do |g|
        standings = standings_by_group[g.id]
        next if standings.size < 2
        team_id, stats = standings[1]
        runner_up_candidates << { team_id: team_id, stats: stats, rank: 2, group: g.name }
      end

      # หารองแชมป์ที่ดีที่สุด
      if runner_up_candidates.any?
        best_runner_up = runner_up_candidates.max_by do |q|
          s = q[:stats]
          gd = s[:gf] - s[:ga]
          [s[:pts], gd, s[:gf]]
        end
        all_qualifiers << best_runner_up if best_runner_up
      end

      return if all_qualifiers.size < 4

      # จัดอันดับ 1-4 ตามผลงาน (แต้ม > ผลต่างประตู > ประตูได้)
      ranked_qualifiers = all_qualifiers.sort_by do |q|
        s = q[:stats]
        gd = s[:gf] - s[:ga]
        [-s[:pts], -gd, -s[:gf]] # เรียงจากมากไปน้อย
      end

      rank1 = ranked_qualifiers[0]
      rank2 = ranked_qualifiers[1]
      rank3 = ranked_qualifiers[2]
      rank4 = ranked_qualifiers[3]

      sf_matches = @division.matches.knockout.where(round_number: 1).order(:position, :id).to_a
      return unless sf_matches.size == 2

      # จับคู่โดยป้องกันไม่ให้ทีมจากสายเดียวกันเจอกัน
      # Default: SF1 = R1 vs R4, SF2 = R2 vs R3
      # ถ้า R1 กับ R4 มาจากสายเดียวกัน → สลับเป็น R1 vs R3, R2 vs R4
      # ถ้า R2 กับ R3 มาจากสายเดียวกัน → สลับเป็น R1 vs R3, R2 vs R4
      
      if rank1[:group] == rank4[:group] || rank2[:group] == rank3[:group]
        # สลับคู่: R1 vs R3, R2 vs R4
        assignments = [
          [rank1[:team_id], rank3[:team_id]],
          [rank2[:team_id], rank4[:team_id]]
        ]
      else
        # Default: R1 vs R4, R2 vs R3
        assignments = [
          [rank1[:team_id], rank4[:team_id]],
          [rank2[:team_id], rank3[:team_id]]
        ]
      end

      sf_matches.each_with_index do |match, idx|
        home_id, away_id = assignments[idx]
        attrs = {}
        attrs[:home_team_id] = home_id if home_id.present?
        attrs[:away_team_id] = away_id if away_id.present?
        match.update!(attrs) if attrs.any?
      end
    end

    # 3 กลุ่ม เข้ารอบ 8 ทีม: จัดอันดับตามผลงานที่ดีที่สุด
    # หลักการ:
    # - เอาอันดับ 1-2 จากทุกสาย (6 ทีม) + รองแชมป์ที่ดีที่สุด 2 ทีม (BP) = 8 ทีม
    # - จัดอันดับ 1-8 ตามผลงาน (แต้ม > ผลต่างประตู > ประตูได้)
    # - จับคู่: R1 vs R8, R2 vs R7, R3 vs R6, R4 vs R5
    # - **สำคัญ:** ทีมจากสายเดียวกันต้องไม่เจอกันในรอบแรก
    def seed_for_8_teams_from_three_groups(groups, standings_by_group)
      return if groups.any? { |g| standings_by_group[g.id].blank? }

      ordered_groups = groups.sort_by(&:name)

      # รวบรวมอันดับ 1-2 จากทุกสาย พร้อมสถิติ
      all_qualifiers = []

      ordered_groups.each do |g|
        standings = standings_by_group[g.id]
        next if standings.blank?

        # อันดับ 1 และ 2 ของสาย
        [0, 1].each do |rank_idx|
          next if rank_idx >= standings.size
          team_id, stats = standings[rank_idx]
          all_qualifiers << { team_id: team_id, stats: stats, rank: rank_idx + 1, group: g.name }
        end
      end

      # เพิ่ม BP (อันดับ 3 ที่ดีที่สุด) จนครบ 8 ทีม
      bp_needed = 8 - all_qualifiers.size
      if bp_needed > 0
        bp_candidates = []
        ordered_groups.each do |g|
          standings = standings_by_group[g.id]
          next if standings.size < 3
          team_id, stats = standings[2] # อันดับ 3
          played = [stats[:played], 1].max
          bp_candidates << { 
            team_id: team_id, 
            stats: stats, 
            rank: 3, 
            group: g.name,
            pts_avg: stats[:pts].to_f / played,
            gd_avg: (stats[:gf] - stats[:ga]).to_f / played,
            gf_avg: stats[:gf].to_f / played
          }
        end

        # เรียง BP ตามค่าเฉลี่ย
        bp_candidates.sort_by! { |c| [-c[:pts_avg], -c[:gd_avg], -c[:gf_avg]] }
        bp_candidates.first(bp_needed).each do |bp|
          all_qualifiers << { team_id: bp[:team_id], stats: bp[:stats], rank: 3, group: bp[:group] }
        end
      end

      return if all_qualifiers.size < 8

      # จัดอันดับ 1-8 ตามผลงาน (แต้ม > ผลต่างประตู > ประตูได้)
      # ใช้ค่าเฉลี่ยต่อนัดเพื่อความยุติธรรม
      ranked_qualifiers = all_qualifiers.sort_by do |q|
        s = q[:stats]
        played = [s[:played], 1].max
        pts_avg = s[:pts].to_f / played
        gd_avg = (s[:gf] - s[:ga]).to_f / played
        gf_avg = s[:gf].to_f / played
        [-pts_avg, -gd_avg, -gf_avg]
      end

      qf_matches = @division.matches.knockout.where(round_number: 1).order(:position, :id).to_a
      return unless qf_matches.size == 4

      # จับคู่โดยป้องกันไม่ให้ทีมจากสายเดียวกันเจอกัน
      # Default: R1 vs R8, R2 vs R7, R3 vs R6, R4 vs R5
      assignments = pair_without_same_group(ranked_qualifiers)

      qf_matches.each_with_index do |match, idx|
        next if idx >= assignments.size
        home_id, away_id = assignments[idx]
        attrs = {}
        attrs[:home_team_id] = home_id if home_id.present?
        attrs[:away_team_id] = away_id if away_id.present?
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
    # หลักการ: 
    # 1. เอาแชมป์กลุ่มทั้งหมด
    # 2. ถ้าไม่พอ เอา Best Performers (BP) จากอันดับถัดไป
    # 3. จับคู่ข้ามสาย ไม่ให้สายเดียวกันเจอกันในรอบแรก
    def seed_generic(groups, standings_by_group)
      return if groups.empty?

      ordered_groups = groups.sort_by(&:name)
      num_groups = ordered_groups.size
      teams_needed = @bracket_size

      # คำนวณว่าต้องเอากี่อันดับจากแต่ละสาย และต้องเอา BP กี่ทีม
      full_rounds = teams_needed / num_groups
      remainder = teams_needed % num_groups

      # รวบรวม qualifiers จากอันดับ 1 ถึง full_rounds ของทุกสาย
      qualifiers = [] # [{team_id:, group_idx:, rank:, label:}, ...]

      ordered_groups.each_with_index do |g, group_idx|
        standings = standings_by_group[g.id] || []
        group_name = g.name.presence || ('A'.ord + group_idx).chr

        (0...full_rounds).each do |rank|
          next if rank >= standings.size
          team_id, stats = standings[rank]

          # ตรวจ tie
          decorated = standings.map { |tid, s| [tid, s[:pts], s[:gf] - s[:ga], s[:gf]] }
          at_rank = decorated[rank]
          if at_rank
            tied = decorated.select { |_, pts, gd, gf| [pts, gd, gf] == [at_rank[1], at_rank[2], at_rank[3]] }
            team_id = nil if tied.size > 1
          end

          qualifiers << { team_id: team_id, group_idx: group_idx, rank: rank, label: "#{rank + 1}#{group_name}" }
        end
      end

      # รวบรวม BP candidates จากอันดับ full_rounds (0-indexed) ของทุกสาย
      # ใช้ค่าเฉลี่ยต่อนัดเพื่อความยุติธรรม (กรณีสายมีจำนวนทีมไม่เท่ากัน)
      if remainder > 0
        bp_candidates = []
        ordered_groups.each_with_index do |g, group_idx|
          standings = standings_by_group[g.id] || []
          next if full_rounds >= standings.size
          team_id, stats = standings[full_rounds]
          played = [stats[:played], 1].max # ป้องกันหารด้วย 0
          bp_candidates << { 
            team_id: team_id, 
            group_idx: group_idx, 
            rank: full_rounds,
            pts: stats[:pts], 
            gd: stats[:gf] - stats[:ga], 
            gf: stats[:gf],
            played: stats[:played],
            # ค่าเฉลี่ยต่อนัด
            pts_avg: stats[:pts].to_f / played,
            gd_avg: (stats[:gf] - stats[:ga]).to_f / played,
            gf_avg: stats[:gf].to_f / played
          }
        end

        # เรียง BP ตามค่าเฉลี่ย: pts_avg > gd_avg > gf_avg (มากไปน้อย)
        bp_candidates.sort_by! { |c| [-c[:pts_avg], -c[:gd_avg], -c[:gf_avg]] }

        # เอา BP ที่ดีที่สุด remainder ทีม
        bp_candidates.first(remainder).each_with_index do |bp, bp_idx|
          qualifiers << { team_id: bp[:team_id], group_idx: bp[:group_idx], rank: full_rounds, label: "BP#{bp_idx + 1}" }
        end
      end

      # ดึงแมตช์รอบแรกของ knockout
      first_round_matches = @division.matches.knockout.where(round_number: 1).order(:position, :id).to_a
      return if first_round_matches.empty?

      # จับคู่ให้ทีมจากสายเดียวกันไม่เจอกันในรอบแรก
      pairs = generate_cross_group_pairs(qualifiers, num_groups)

      first_round_matches.each_with_index do |match, idx|
        next if idx >= pairs.size
        home_qual, away_qual = pairs[idx]

        attrs = {}
        attrs[:home_team_id] = home_qual[:team_id] if home_qual && home_qual[:team_id].present?
        attrs[:away_team_id] = away_qual[:team_id] if away_qual && away_qual[:team_id].present?
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
