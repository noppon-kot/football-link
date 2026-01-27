class Group < ApplicationRecord
  belongs_to :tournament_division
  has_many :matches, dependent: :destroy
  has_many :standings_snapshots, dependent: :destroy
end
