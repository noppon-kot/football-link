class TournamentDivision < ApplicationRecord
  belongs_to :tournament

  validates :name, presence: true, unless: :marked_for_destruction?

  has_many :team_registrations, dependent: :nullify
end
