class AddKnockoutFieldsToMatches < ActiveRecord::Migration[7.2]
  def change
    add_column :matches, :stage, :integer, null: false, default: 0
    add_column :matches, :round_number, :integer
    add_column :matches, :round_label, :string

    add_index :matches, :stage
    add_index :matches, [:tournament_division_id, :stage, :round_number], name: "index_matches_on_division_stage_round"
  end
end
