# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

organizer = User.find_or_create_by!(email: "organizer@example.com") do |u|
  u.name  = "Thunder Organizer"
  u.phone = "091-234-5678"
  u.role  = 0 # organizer
end

field_owner = User.find_or_create_by!(email: "field.owner@example.com") do |u|
  u.name  = "Supachai Field Owner"
  u.phone = "089-000-1111"
  u.role  = 2 # field_owner
end

kk_arena = Field.find_or_create_by!(name: "KK Arena") do |f|
  f.address        = "ถนนมิตรภาพ มข. ขอนแก่น"
  f.city           = "Khon Kaen"
  f.province       = "ขอนแก่น"
  f.latitude       = 16.4410
  f.longitude      = 102.8280
  f.field_type     = 0 # turf
  f.price_per_hour = 1200
  f.user           = field_owner
end

thunder_arena = Field.find_or_create_by!(name: "Thunder Arena") do |f|
  f.address        = "ในเมือง ขอนแก่น"
  f.city           = "Khon Kaen"
  f.province       = "ขอนแก่น"
  f.latitude       = 16.4415
  f.longitude      = 102.8290
  f.field_type     = 0
  f.price_per_hour = 1500
  f.user           = field_owner
end

thunder_cup_u21 = Tournament.find_or_create_by!(title: "THUNDER CUP U21") do |t|
  t.description   = "ทัวร์นาเมนต์เยาวชน U21 แข่ง 7 คน ที่ Thunder Arena"
  t.location_name = "Thunder Arena"
  t.city          = "Khon Kaen"
  t.province      = "ขอนแก่น"
  t.age_category  = "U21"
  t.team_size     = 7
  t.entry_fee     = 3000
  t.prize_amount  = 5000
  t.status        = 1 # published
  t.organizer     = organizer
  t.field         = thunder_arena
end

kk_cup_7s = Tournament.find_or_create_by!(title: "KHON KAEN CUP 7s") do |t|
  t.description   = "ฟุตบอล 7 คน ชิงเงินรางวัลที่ KK Arena"
  t.location_name = "KK Arena"
  t.city          = "Khon Kaen"
  t.province      = "ขอนแก่น"
  t.age_category  = "เปิดกว้าง"
  t.team_size     = 7
  t.entry_fee     = 3500
  t.prize_amount  = 6000
  t.status        = 1
  t.organizer     = organizer
  t.field         = kk_arena
end

team_rajan = Team.find_or_create_by!(name: "Rajan FC") do |team|
  team.contact_name  = "โค้ชราชัน"
  team.contact_phone = "081-111-1111"
  team.city          = "Khon Kaen"
  team.province      = "ขอนแก่น"
end

team_sabuy = Team.find_or_create_by!(name: "สบาย FC") do |team|
  team.contact_name  = "โค้ชสบาย"
  team.contact_phone = "082-222-2222"
  team.city          = "Khon Kaen"
  team.province      = "ขอนแก่น"
end

team_kku = Team.find_or_create_by!(name: "KKU Academy") do |team|
  team.contact_name  = "โค้ชมข"
  team.contact_phone = "083-333-3333"
  team.city          = "Khon Kaen"
  team.province      = "ขอนแก่น"
end

TeamRegistration.find_or_create_by!(team: team_rajan, tournament: thunder_cup_u21) do |reg|
  reg.status = 0 # interested
  reg.notes  = "อยากทราบรายละเอียดเพิ่ม"
end

TeamRegistration.find_or_create_by!(team: team_sabuy, tournament: thunder_cup_u21) do |reg|
  reg.status = 1 # applied
  reg.notes  = "ส่งรายชื่อนักเตะครบแล้ว"
end

TeamRegistration.find_or_create_by!(team: team_kku, tournament: kk_cup_7s) do |reg|
  reg.status = 3 # paid
  reg.notes  = "โอนค่าสมัครแล้ว"
end

# เพิ่มทัวร์นาเมนต์ mock เพิ่มเติม (รวมประมาณ 10 รายการ)
additional_tournaments = [
  { title: "THUNDER CUP U12", age: "U12", field: thunder_arena, fee: 2000, prize: 3000 },
  { title: "THUNDER CUP U16", age: "U16", field: thunder_arena, fee: 2500, prize: 4000 },
  { title: "KK CITY LEAGUE", age: "เปิดกว้าง", field: kk_arena, fee: 3000, prize: 7000 },
  { title: "KHON KAEN SCHOOL CUP", age: "U18", field: kk_arena, fee: 1800, prize: 3500 },
  { title: "NIGHT STREET CUP", age: "เปิดกว้าง", field: thunder_arena, fee: 3200, prize: 6500 },
  { title: "SUMMER FUTSAL U14", age: "U14", field: thunder_arena, fee: 2200, prize: 3800 },
  { title: "ALUMNI FRIENDLY CUP", age: "เปิดกว้าง", field: kk_arena, fee: 2800, prize: 5000 },
  { title: "UNIVERSITY CUP U21", age: "U21", field: kk_arena, fee: 3200, prize: 8000 }
]

more_tournaments = []

additional_tournaments.each do |cfg|
  more_tournaments << Tournament.find_or_create_by!(title: cfg[:title]) do |t|
    t.description   = "ทัวร์นาเมนต์ฟุตบอลเดินสายที่จัดขึ้นในขอนแก่น"
    t.location_name = cfg[:field].name
    t.city          = cfg[:field].city
    t.province      = cfg[:field].province
    t.age_category  = cfg[:age]
    t.team_size     = 7
    t.entry_fee     = cfg[:fee]
    t.prize_amount  = cfg[:prize]
    t.status        = 1
    t.organizer     = organizer
    t.field         = cfg[:field]
  end
end

# สร้างทีมเพิ่มเพื่อให้มีทีมสนใจ/สมัครเยอะ ๆ
teams = [team_rajan, team_sabuy, team_kku]

5.times do |i|
  teams << Team.find_or_create_by!(name: "Khon Kaen FC #{i + 1}") do |team|
    team.contact_name  = "โค้ช KK #{i + 1}"
    team.contact_phone = "090-000-#{(1000 + i)}"
    team.city          = "Khon Kaen"
    team.province      = "ขอนแก่น"
  end
end

all_tournaments = [thunder_cup_u21, kk_cup_7s] + more_tournaments

# เคลียร์ registration เก่าทิ้งก่อนสร้างใหม่ (เพื่อความง่ายในการลอง seed ซ้ำ)
TeamRegistration.delete_all

all_tournaments.each_with_index do |tournament, idx|
  # ให้แต่ละทัวร์มีทีมสนใจ/สมัคร/ยืนยัน/จ่ายแล้วอย่างละหลายทีม
  teams.each_with_index do |team, t_idx|
    status = case (t_idx + idx) % 4
             when 0 then 0 # interested
             when 1 then 1 # applied
             when 2 then 2 # confirmed
             else 3        # paid
             end

    TeamRegistration.create!(
      team: team,
      tournament: tournament,
      status: status,
      notes: "mock registration"
    )
  end
end
