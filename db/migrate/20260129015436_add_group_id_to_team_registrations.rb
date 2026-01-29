class AddGroupIdToTeamRegistrations < ActiveRecord::Migration[7.2]
  def change
    add_reference :team_registrations, :group, null: true, foreign_key: true
  end
end
