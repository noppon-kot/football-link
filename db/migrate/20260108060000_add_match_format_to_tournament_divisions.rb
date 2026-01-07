class AddMatchFormatToTournamentDivisions < ActiveRecord::Migration[7.2]
  def change
    add_column :tournament_divisions, :match_format, :string, default: "single_leg", null: false
  end
end
