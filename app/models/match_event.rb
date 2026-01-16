class MatchEvent < ApplicationRecord
  belongs_to :match
  belongs_to :tournament_player

  enum event_type: { goal: 0, yellow_card: 1, red_card: 2 }
end
