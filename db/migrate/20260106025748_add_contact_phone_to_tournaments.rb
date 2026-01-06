class AddContactPhoneToTournaments < ActiveRecord::Migration[7.2]
  def change
    add_column :tournaments, :contact_phone, :string
  end
end
