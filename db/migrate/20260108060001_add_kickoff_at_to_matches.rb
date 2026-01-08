class AddKickoffAtToMatches < ActiveRecord::Migration[7.2]
  def change
    add_column :matches, :kickoff_at, :datetime
  end
end
