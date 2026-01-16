class CreateMatchLineupPlayers < ActiveRecord::Migration[7.1]
  def change
    create_table :match_lineup_players do |t|
      t.references :match_lineup, null: false, foreign_key: true
      t.references :tournament_player, null: false, foreign_key: true
      t.integer :role, null: false

      t.timestamps
    end

    add_index :match_lineup_players, [:match_lineup_id, :tournament_player_id], unique: true, name: "index_mlp_on_lineup_and_player"
  end
end
