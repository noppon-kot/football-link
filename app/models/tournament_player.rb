class TournamentPlayer < ApplicationRecord
  belongs_to :team_registration

  has_one_attached :photo

  validates :full_name, presence: true
end
