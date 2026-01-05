class CreateTournamentDivisions < ActiveRecord::Migration[7.2]
  def change
    create_table :tournament_divisions do |t|
      t.references :tournament, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position

      t.timestamps
    end
  end
end
