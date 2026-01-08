class AddPkRulesToDivisionsAndMatches < ActiveRecord::Migration[7.2]
  def change
    # กติกาจุดโทษในระดับรุ่น (division)
    add_column :tournament_divisions, :draw_mode, :string, default: "normal", null: false
    add_column :tournament_divisions, :points_pk_win, :integer
    add_column :tournament_divisions, :points_pk_loss, :integer

    # ธงและข้อมูลผู้ชนะจุดโทษในแต่ละแมตช์
    add_column :matches, :decided_by_penalty, :boolean, default: false, null: false
    add_column :matches, :penalty_winner_side, :string
  end
end
