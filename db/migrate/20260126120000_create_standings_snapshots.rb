class CreateStandingsSnapshots < ActiveRecord::Migration[7.2]
  def change
    create_table :standings_snapshots do |t|
      t.references :tournament_division, null: false, foreign_key: true
      t.references :group, null: true, foreign_key: true
      t.datetime :generated_at

      t.timestamps
    end

    add_index :standings_snapshots, [:tournament_division_id, :group_id], unique: true
  end
end
