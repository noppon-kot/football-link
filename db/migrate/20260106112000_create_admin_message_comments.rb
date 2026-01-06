class CreateAdminMessageComments < ActiveRecord::Migration[7.2]
  def change
    create_table :admin_message_comments do |t|
      t.references :admin_message, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false

      t.timestamps
    end
  end
end
