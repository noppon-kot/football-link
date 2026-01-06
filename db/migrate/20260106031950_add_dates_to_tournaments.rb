class AddDatesToTournaments < ActiveRecord::Migration[7.2]
  def change
    add_column :tournaments, :competition_date, :date
    add_column :tournaments, :registration_open_on, :date
    add_column :tournaments, :registration_close_on, :date
  end
end
