class TournamentDivision < ApplicationRecord
  belongs_to :tournament

  validates :name, presence: true

  has_many :team_registrations, dependent: :nullify
end
