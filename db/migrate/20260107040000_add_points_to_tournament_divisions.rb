class AddPointsToTournamentDivisions < ActiveRecord::Migration[7.2]
  def change
    add_column :tournament_divisions, :points_win, :integer, null: false, default: 3
    add_column :tournament_divisions, :points_draw, :integer, null: false, default: 1
    add_column :tournament_divisions, :points_loss, :integer, null: false, default: 0
  end
end
