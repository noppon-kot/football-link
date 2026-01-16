class CreateTournamentPlayers < ActiveRecord::Migration[7.2]
  def change
    create_table :tournament_players do |t|
      t.references :team_registration, null: false, foreign_key: true
      t.string :full_name, null: false
      t.date :birth_date
      t.integer :jersey_number
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :tournament_players, [:team_registration_id, :jersey_number]
  end
end
