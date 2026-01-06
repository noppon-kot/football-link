class AddLineIdToTournaments < ActiveRecord::Migration[7.2]
  def change
    add_column :tournaments, :line_id, :string
  end
end
