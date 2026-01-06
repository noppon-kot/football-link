class AddLineIdToTeams < ActiveRecord::Migration[7.2]
  def change
    add_column :teams, :line_id, :string
  end
end
