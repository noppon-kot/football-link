class MatchLineupPlayer < ApplicationRecord
  belongs_to :match_lineup
  belongs_to :tournament_player

  enum role: { starter: 0, substitute: 1 }
end
