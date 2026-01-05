class AddTournamentDivisionToTeamRegistrations < ActiveRecord::Migration[7.2]
  def change
    add_reference :team_registrations, :tournament_division, foreign_key: true, null: true
  end
end
