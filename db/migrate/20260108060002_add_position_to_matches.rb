class AddPositionToMatches < ActiveRecord::Migration[7.2]
  def change
    add_column :matches, :position, :integer
  end
end
