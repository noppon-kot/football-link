class AddTiebreakerRankToTeamRegistrations < ActiveRecord::Migration[7.2]
  def change
    add_column :team_registrations, :tiebreaker_rank, :integer
  end
end
