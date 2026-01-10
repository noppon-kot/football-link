module Tournaments
  class AutoSeedKnockoutService
    Result = Struct.new(:success?, :message, keyword_init: true)

    def initialize(division:, bracket_size:)
      @division = division
      @bracket_size = bracket_size.to_i
    end

    def call
      return Result.new(success?: true, message: nil) unless [4, 8].include?(@bracket_size)

      groups = @division.groups.order(:name).to_a
      unless groups.size == 2
        return Result.new(success?: false, message: "auto-seed รองรับเฉพาะกรณีมี 2 สาย (เช่น สาย A และสาย B)")
      end

      standings_by_group = compute_standings(groups)

      case @bracket_size
      when 8
        seed_for_8_teams(groups, standings_by_group)
      when 4
        seed_for_4_teams(groups, standings_by_group)
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
