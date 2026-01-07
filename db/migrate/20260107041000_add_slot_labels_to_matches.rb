class AddSlotLabelsToMatches < ActiveRecord::Migration[7.2]
  def change
    add_column :matches, :home_slot_label, :string, null: false, default: ""
    add_column :matches, :away_slot_label, :string, null: false, default: ""

    change_column_null :matches, :home_team_id, true
    change_column_null :matches, :away_team_id, true
  end
end
