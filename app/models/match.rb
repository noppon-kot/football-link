class Match < ApplicationRecord
  belongs_to :tournament_division
  belongs_to :group, optional: true
  belongs_to :home_team, class_name: "Team", optional: true
  belongs_to :away_team, class_name: "Team", optional: true

  enum status: { scheduled: 0, finished: 1 }

  def winner
    return nil unless finished? && home_score.present? && away_score.present?
    return nil if home_score == away_score

    home_score > away_score ? home_team : away_team
  end

  def home_name
    home_team&.name.presence || home_slot_label.presence || "-"
  end

  def away_name
    away_team&.name.presence || away_slot_label.presence || "-"
  end
end
