class UpdateStandingsSnapshotsForeignKeys < ActiveRecord::Migration[7.2]
  def change
    remove_foreign_key :standings_snapshots, :groups
    add_foreign_key :standings_snapshots, :groups, column: :group_id, on_delete: :cascade

    remove_foreign_key :standings_snapshots, :tournament_divisions
    add_foreign_key :standings_snapshots, :tournament_divisions, column: :tournament_division_id, on_delete: :cascade
  end
end
