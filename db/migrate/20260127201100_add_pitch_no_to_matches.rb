class AddPitchNoToMatches < ActiveRecord::Migration[7.2]
  def change
    add_column :matches, :pitch_no, :integer, null: false, default: 1
    add_index :matches, :pitch_no
  end
end
