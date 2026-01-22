class AddLocalAuthFieldsToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :username, :string
    add_column :users, :password_digest, :string
    add_column :users, :security_question, :string
    add_column :users, :security_answer_digest, :string

    add_index :users, :username, unique: true
  end
end
