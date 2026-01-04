class CreateTeamRegistrations < ActiveRecord::Migration[7.2]
  def change
    create_table :team_registrations do |t|
      t.integer :status
      t.text :notes
      t.references :team, null: false, foreign_key: true
      t.references :tournament, null: false

      t.timestamps
    end
  end
end
