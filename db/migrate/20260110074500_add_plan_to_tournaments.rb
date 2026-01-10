class AddPlanToTournaments < ActiveRecord::Migration[7.1]
  def change
    add_column :tournaments, :plan, :integer, default: 0, null: false
  end
end
