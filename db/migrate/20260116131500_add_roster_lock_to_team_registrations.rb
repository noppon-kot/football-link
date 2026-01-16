class AddRosterLockToTeamRegistrations < ActiveRecord::Migration[7.2]
  def change
    add_column :team_registrations, :roster_locked, :boolean, null: false, default: false
    add_column :team_registrations, :roster_submitted_at, :datetime
    add_reference :team_registrations, :roster_submitted_by_user, null: true, foreign_key: { to_table: :users }

    add_index :team_registrations, :roster_locked
  end
end
