class AddLoginCountToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :login_count, :integer, default: 0, null: false
  end
end
