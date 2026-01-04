class CreateTournaments < ActiveRecord::Migration[7.2]
  def change
    create_table :tournaments do |t|
      t.string :title
      t.text :description
      t.string :location_name
      t.string :city
      t.string :province
      t.string :age_category
      t.integer :team_size
      t.integer :entry_fee
      t.integer :prize_amount
      t.integer :status
      t.references :organizer, null: false, foreign_key: { to_table: :users }
      t.references :field, null: false

      t.timestamps
    end
  end
end
