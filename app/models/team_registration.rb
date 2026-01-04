class TeamRegistration < ApplicationRecord
  belongs_to :team
  belongs_to :tournament
  # status: 0 = interested, 1 = applied, 2 = confirmed, 3 = paid
  enum status: { interested: 0, applied: 1, confirmed: 2, paid: 3 }
end
