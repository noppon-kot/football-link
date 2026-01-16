class TournamentPlayer < ApplicationRecord
  belongs_to :team_registration

  has_many :match_lineup_players, dependent: :destroy
  has_many :match_lineups, through: :match_lineup_players
  has_many :match_events, dependent: :destroy

  has_one_attached :photo, dependent: :purge_later

  validates :full_name, presence: true

  def age
    return nil unless birth_date

    today = Date.current
    years = today.year - birth_date.year
    had_birthday = (today.month > birth_date.month) || (today.month == birth_date.month && today.day >= birth_date.day)
    years -= 1 unless had_birthday
    years
  end
end
