class AddKnockoutPatternToTournamentDivisions < ActiveRecord::Migration[7.2]
  def change
    # knockout_pattern: รูปแบบการจับคู่น็อคเอาท์
    # - "cross" (default): สายที่ห่างกันเจอกัน (A vs C, B vs D)
    # - "adjacent": สายที่ติดกันเจอกัน (A vs B, C vs D)
    add_column :tournament_divisions, :knockout_pattern, :string, default: "cross"
  end
end
