class Group < ApplicationRecord
  belongs_to :tournament_division
  has_many :matches, dependent: :destroy
end
