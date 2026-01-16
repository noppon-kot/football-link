class BackfillTeamRegistrationManagers < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      INSERT INTO team_registration_managers (team_registration_id, user_id, created_at, updated_at)
      SELECT id, manager_user_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM team_registrations
      WHERE manager_user_id IS NOT NULL
      ON CONFLICT (team_registration_id, user_id) DO NOTHING
    SQL
  end

  def down
    # no-op
  end
end
