class AddPackageToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :package, :integer, default: 0, null: false
    add_index :users, :package
  end
end
