class CreateMatches < ActiveRecord::Migration[7.2]
  def change
    create_table :matches do |t|
      t.references :tournament_division, null: false, foreign_key: true
      t.references :group, foreign_key: true
      t.references :home_team, null: false, foreign_key: { to_table: :teams }
      t.references :away_team, null: false, foreign_key: { to_table: :teams }
      t.integer :home_score
      t.integer :away_score
      t.integer :status, null: false, default: 0

      t.timestamps
    end
  end
end
