class CreateTeamRegistrationManagers < ActiveRecord::Migration[7.1]
  def change
    create_table :team_registration_managers do |t|
      t.references :team_registration, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :team_registration_managers,
              [:team_registration_id, :user_id],
              unique: true,
              name: "index_trm_on_team_registration_id_and_user_id"
  end
end
