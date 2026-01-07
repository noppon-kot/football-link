class TournamentDivision < ApplicationRecord
  belongs_to :tournament

  validates :name, presence: true, unless: :marked_for_destruction?

  has_many :team_registrations, dependent: :nullify
  has_many :groups, dependent: :destroy
  has_many :matches, dependent: :destroy

  MATCH_FORMATS = %w[single_leg home_away].freeze

  def match_format
    value = self[:match_format].presence || "single_leg"
    MATCH_FORMATS.include?(value) ? value : "single_leg"
  end
end
