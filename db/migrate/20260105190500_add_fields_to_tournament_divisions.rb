class AddFieldsToTournamentDivisions < ActiveRecord::Migration[7.2]
  def change
    add_column :tournament_divisions, :entry_fee, :integer
    add_column :tournament_divisions, :prize_amount, :integer
  end
end
