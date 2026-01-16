class TournamentPlayer < ApplicationRecord
  belongs_to :team_registration

  has_many :match_lineup_players, dependent: :destroy
  has_many :match_lineups, through: :match_lineup_players
  has_many :match_events, dependent: :destroy

  has_one_attached :photo, dependent: :purge_later

  validates :full_name, presence: true
end
