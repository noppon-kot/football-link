class CreateMatchEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :match_events do |t|
      t.references :match, null: false, foreign_key: true
      t.references :tournament_player, null: false, foreign_key: true
      t.integer :event_type, null: false

      t.timestamps
    end

    add_index :match_events, [:match_id, :event_type]
  end
end
