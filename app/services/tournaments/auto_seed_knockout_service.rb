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

        sorted = stats.map { |tid, s| [tid, s] }
                     .sort_by { |tid, s| [-s[:pts], -(s[:gf] - s[:ga]), -s[:gf], Team.find(tid).name] }
        standings_by_group[group.id] = sorted
      end

      standings_by_group
    end

    # 3 กลุ่ม เข้ารอบ 4 ทีม: เอาแชมป์กลุ่มทั้ง 3 + รองแชมป์ที่ดีที่สุด 1 ทีม
    # ถ้ามีรองแชมป์ที่ดีที่สุดมากกว่า 1 ทีมที่แต้ม/ผลต่าง/ประตูได้เท่ากันหมด ให้ฝ่ายจัดเลือกเอง
    # return nil ถ้าสำเร็จ, หรือข้อความ error ถ้าตัดสินไม่ได้
    def seed_for_4_teams_from_three_groups(groups, standings_by_group)
      return if groups.any? { |g| standings_by_group[g.id].blank? }

      # เรียงกลุ่มตามชื่อเพื่อให้ A,B,C มีลำดับชัดเจน
      ordered_groups = groups.sort_by(&:name)

      # แชมป์กลุ่ม (อันดับ 1 ของแต่ละกลุ่ม)
      group_winners = []

      ordered_groups.each do |g|
        standings = standings_by_group[g.id]
        next if standings.blank?

        # หาอันดับ 1 จากแต้ม > ผลต่างประตู > ประตูได้
        decorated = standings.map do |team_id, s|
          goal_diff = s[:gf] - s[:ga]
          [team_id, s[:pts], goal_diff, s[:gf]]
        end

        best = decorated.max_by { |_, pts, gd, gf| [pts, gd, gf] }
        best_id, best_pts, best_gd, best_gf = best

        # ตรวจว่ามีหลายทีมในสายนี้ที่สถิติแต้ม/ผลต่าง/ประตูได้เท่ากันหมดหรือไม่
        tied_best = decorated.select { |_, pts, gd, gf| [pts, gd, gf] == [best_pts, best_gd, best_gf] }
        if tied_best.size > 1
          # แชมป์กลุ่มตัดสินไม่ได้ ปล่อยให้ผู้จัดเลือกเองในหน้า knockout
          group_winners << nil
        else
          group_winners << best_id
        end
      end

      # รวบรวมรองแชมป์ (อันดับ 2) เป็น candidate
      runner_up_candidates = []

      ordered_groups.each do |g|
        standings = standings_by_group[g.id]
        next if standings.size < 2
        team_id, stats = standings[1] # อันดับ 2
        runner_up_candidates << [team_id, stats]
      end

      return if runner_up_candidates.empty?

      # หารองแชมป์ที่ดีที่สุด: แต้ม > ผลต่างประตู > ประตูได้ > ชื่อทีม
      decorated = runner_up_candidates.map do |team_id, s|
        team = Team.find(team_id)
        goal_diff = s[:gf] - s[:ga]
        [team_id, s[:pts], goal_diff, s[:gf], team.name]
      end

      # หาค่าสูงสุด
      max_vals = decorated.max_by { |_, pts, gd, gf, name| [pts, gd, gf, name] }
      best_team_id, max_pts, max_gd, max_gf, max_name = max_vals

      # ดูว่ามีกี่ทีมที่มีค่านี้เท่ากันหมด
      tied = decorated.select { |_, pts, gd, gf, name| [pts, gd, gf, name] == [max_pts, max_gd, max_gf, max_name] }

      if tied.size > 1
        # รองแชมป์ที่ดีที่สุดตัดสินไม่ได้ ปล่อยให้ผู้จัดเลือกทีมที่ 4 เอง
        best_runner_up_id = nil
      else
        best_runner_up_id = best_team_id
      end

      # จัดรอบ 4 ทีม: SF1 = A1 vs รองแชมป์ที่ดีที่สุด, SF2 = B1 vs C1
      a_top, b_top, c_top = group_winners

      sf_matches = @division.matches.knockout.where(round_number: 1).order(:position, :id).to_a
      return unless sf_matches.size == 2

      assignments = [
        [a_top, best_runner_up_id],
        [b_top, c_top]
      ]

      sf_matches.each_with_index do |match, idx|
        home_id, away_id = assignments[idx]
        attrs = {}
        attrs[:home_team_id] = home_id if home_id.present?
        attrs[:away_team_id] = away_id if away_id.present?
        match.update!(attrs) if attrs.any?
      end
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
