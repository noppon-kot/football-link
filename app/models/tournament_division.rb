class TournamentDivision < ApplicationRecord
  belongs_to :tournament

  validates :name, presence: true, unless: :marked_for_destruction?

  has_many :team_registrations, dependent: :nullify
  has_many :groups, dependent: :destroy
  has_many :matches, dependent: :destroy
end
