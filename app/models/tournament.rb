class Tournament < ApplicationRecord
  belongs_to :organizer, class_name: "User"
  belongs_to :field

  # status: 0 = draft, 1 = published, 2 = closed
  enum status: { draft: 0, published: 1, closed: 2 }

  has_many :team_registrations, dependent: :destroy
  has_many :teams, through: :team_registrations
  has_many :tournament_divisions, dependent: :destroy

  accepts_nested_attributes_for :tournament_divisions, allow_destroy: true, reject_if: proc { |attrs|
    attrs["name"].blank? && attrs["entry_fee"].blank? && attrs["prize_amount"].blank?
  }
end
