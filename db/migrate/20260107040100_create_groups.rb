class CreateGroups < ActiveRecord::Migration[7.2]
  def change
    create_table :groups do |t|
      t.references :tournament_division, null: false, foreign_key: true
      t.string :name, null: false

      t.timestamps
    end
  end
end
