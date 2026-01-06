class CreateAdminMessages < ActiveRecord::Migration[7.2]
  def change
    create_table :admin_messages do |t|
      t.references :user, null: false, foreign_key: true
      t.references :tournament, null: true, foreign_key: true
      t.string :subject, null: false
      t.text :body, null: false
      t.integer :status, null: false, default: 0
      t.string :message_type
      t.text :admin_reply
      t.datetime :replied_at

      t.timestamps
    end
  end
end
