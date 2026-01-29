class TeamRegistration < ApplicationRecord
  belongs_to :team
  belongs_to :tournament
  belongs_to :tournament_division, optional: true
  belongs_to :manager_user, class_name: "User", optional: true
  belongs_to :group, optional: true

  has_many :team_registration_managers, dependent: :destroy
  has_many :manager_users, through: :team_registration_managers, source: :user

  has_many :tournament_players, dependent: :destroy

  before_destroy :nullify_match_lineups

  # status: 0 = interested, 1 = applied, 2 = confirmed, 3 = paid
  enum status: { interested: 0, applied: 1, confirmed: 2, paid: 3 }

  scope :confirmed_for_competition, -> { where(status: [:confirmed, :paid]) }

  private

  def nullify_match_lineups
    MatchLineup.where(team_registration_id: id).update_all(team_registration_id: nil)
  end
end
