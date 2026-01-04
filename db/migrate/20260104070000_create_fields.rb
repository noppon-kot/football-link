class CreateFields < ActiveRecord::Migration[7.2]
  def change
    create_table :fields do |t|
      t.string :name
      t.string :address
      t.string :city
      t.string :province
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.integer :field_type
      t.integer :price_per_hour
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
