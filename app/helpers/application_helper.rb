module ApplicationHelper
  def tournament_first_match_date(tournament)
    division_ids = tournament.tournament_divisions.select(:id)
    Match.where(tournament_division_id: division_ids)
         .where.not(kickoff_at: nil)
         .minimum(:kickoff_at)
         &.to_date
  end

  def tournament_start_date_label(tournament)
    first_date = tournament_first_match_date(tournament)
    return first_date.strftime("%d/%m/%Y") if first_date.present?

    tournament.competition_date&.strftime("%d/%m/%Y") || "-"
  end

  def tournament_competition_date_label(tournament)
    division_ids = tournament.tournament_divisions.select(:id)
    matches = Match.where(tournament_division_id: division_ids).where.not(kickoff_at: nil)

    total_matches = Match.where(tournament_division_id: division_ids).count
    if total_matches.positive? && matches.count == total_matches
      first_date = matches.minimum(:kickoff_at)&.to_date
      last_date = matches.maximum(:kickoff_at)&.to_date

      return "-" if first_date.blank? || last_date.blank?
      return first_date.strftime("%d/%m/%Y") if first_date == last_date

      return "#{first_date.strftime('%d/%m/%Y')} - #{last_date.strftime('%d/%m/%Y')}"
    end

    tournament.competition_date&.strftime("%d/%m/%Y") || "-"
  end
end
