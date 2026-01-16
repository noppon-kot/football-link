class MatchLineup < ApplicationRecord
  belongs_to :match
  belongs_to :team_registration, optional: true
  belongs_to :submitted_by_user, class_name: "User", optional: true

  has_many :match_lineup_players, dependent: :destroy
  has_many :tournament_players, through: :match_lineup_players

  enum side: { home: 0, away: 1 }
end
