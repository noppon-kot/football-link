class Team < ApplicationRecord
  has_many :team_registrations, dependent: :destroy
  has_many :tournaments, through: :team_registrations
end
