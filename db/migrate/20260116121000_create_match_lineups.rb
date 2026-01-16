class CreateMatchLineups < ActiveRecord::Migration[7.1]
  def change
    create_table :match_lineups do |t|
      t.references :match, null: false, foreign_key: true
      t.integer :side, null: false
      t.references :team_registration, null: true, foreign_key: true
      t.references :submitted_by_user, null: true, foreign_key: { to_table: :users }
      t.datetime :submitted_at
      t.boolean :locked, null: false, default: false

      t.timestamps
    end

    add_index :match_lineups, [:match_id, :side], unique: true
  end
end
