class AddManagerUserToTeamRegistrations < ActiveRecord::Migration[7.2]
  def change
    add_reference :team_registrations, :manager_user, foreign_key: { to_table: :users }, null: true
  end
end
