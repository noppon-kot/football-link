class StandingsSnapshot < ApplicationRecord
  belongs_to :tournament_division
  belongs_to :group, optional: true

  has_one_attached :image

  validates :tournament_division_id, presence: true

  validates :group_id, uniqueness: { scope: :tournament_division_id, allow_nil: true }
end
