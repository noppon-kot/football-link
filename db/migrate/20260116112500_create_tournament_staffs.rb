class CreateTournamentStaffs < ActiveRecord::Migration[7.1]
  def change
    create_table :tournament_staffs do |t|
      t.references :tournament, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :tournament_staffs,
              [:tournament_id, :user_id],
              unique: true,
              name: "index_tournament_staffs_on_tournament_id_and_user_id"
  end
end
