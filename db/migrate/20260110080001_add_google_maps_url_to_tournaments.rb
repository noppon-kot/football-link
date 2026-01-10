class AddGoogleMapsUrlToTournaments < ActiveRecord::Migration[7.0]
  def change
    add_column :tournaments, :google_maps_url, :string
  end
end
