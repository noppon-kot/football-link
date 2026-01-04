class CreateTeams < ActiveRecord::Migration[7.2]
  def change
    create_table :teams do |t|
      t.string :name
      t.string :contact_name
      t.string :contact_phone
      t.string :city
      t.string :province

      t.timestamps
    end
  end
end
