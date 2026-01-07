puts "Clearing existing data..."

AdminMessageComment.delete_all if defined?(AdminMessageComment)
AdminMessage.delete_all        if defined?(AdminMessage)

TeamRegistration.delete_all
Team.delete_all
TournamentDivision.delete_all
Tournament.delete_all
Field.delete_all
User.delete_all

puts "Seeding users..."

admin = User.create!(
  name:  "Admin",
  email: "admin@example.com",
  phone: "080-000-0000",
  role:  :organizer
)

user1 = User.create!(
  name:  "User One",
  email: "user1@example.com",
  phone: "091-111-1111",
  role:  :player
)

user2 = User.create!(
  name:  "User Two",
  email: "user2@example.com",
  phone: "092-222-2222",
  role:  :player
)

user3 = User.create!(
  name:  "User Three",
  email: "user3@example.com",
  phone: "093-333-3333",
  role:  :player
)

puts "Seeding fields..."

kk_arena = Field.create!(
  name:           "KK Arena",
  address:        "ถนนมิตรภาพ มข. ขอนแก่น",
  city:           "Khon Kaen",
  province:       "ขอนแก่น",
  latitude:       16.4410,
  longitude:      102.8280,
  field_type:     :turf,
  price_per_hour: 1200,
  user:           admin
)

thunder_arena = Field.create!(
  name:           "Thunder Arena",
  address:        "ในเมือง ขอนแก่น",
  city:           "Khon Kaen",
  province:       "ขอนแก่น",
  latitude:       16.4415,
  longitude:      102.8290,
  field_type:     :turf,
  price_per_hour: 1500,
  user:           admin
)

kalasin_arena = Field.create!(
  name:           "Kalasin Arena",
  address:        "ตัวเมือง กาฬสินธุ์",
  city:           "Kalasin",
  province:       "กาฬสินธุ์",
  latitude:       16.4320,
  longitude:      103.5050,
  field_type:     :turf,
  price_per_hour: 1300,
  user:           admin
)

srk_arena = Field.create!(
  name:           "Mahasarakham Sport Park",
  address:        "ตัวเมือง มหาสารคาม",
  city:           "Maha Sarakham",
  province:       "มหาสารคาม",
  latitude:       16.1840,
  longitude:      103.3020,
  field_type:     :turf,
  price_per_hour: 1400,
  user:           admin
)

puts "Seeding tournaments with multiple divisions..."

def create_tournament_with_divisions(attrs)
  divisions = attrs.delete(:divisions)
  tournament = Tournament.create!(attrs)

  divisions.each_with_index do |div_cfg, idx|
    tournament.tournament_divisions.create!(
      name:         div_cfg[:name],
      entry_fee:    div_cfg[:entry_fee],
      prize_amount: div_cfg[:prize_amount],
      position:     idx
    )
  end

  primary = tournament.tournament_divisions.first
  if primary
    tournament.update!(
      age_category: primary.name,
      entry_fee:    primary.entry_fee,
      prize_amount: primary.prize_amount
    )
  end

  tournament
end

tournaments = []

tournaments << create_tournament_with_divisions(
  title:         "THUNDER CUP SERIES",
  description:   "ทัวร์นาเมนต์ฟุตบอลเดินสายหลายช่วงอายุ แข่ง 7 คน ที่ Thunder Arena",
  location_name: thunder_arena.name,
  city:          thunder_arena.city,
  province:      thunder_arena.province,
  line_id:       "thunder.cup.line",
  contact_phone: "081-000-1000",
  team_size:     7,
  status:        :active,
  registration_open_on: Date.today,
  registration_close_on: Date.today + 14,
  competition_date: Date.today + 21,
  organizer:     admin,
  field:         thunder_arena,
  divisions: [
    { name: "12 ปี",            entry_fee: 1499, prize_amount: 3000 },
    { name: "ประชาชนทั่วไป",  entry_fee: 1999, prize_amount: 6000 },
    { name: "35+",             entry_fee: 1799, prize_amount: 5000 },
    { name: "40+",             entry_fee: 1599, prize_amount: 4000 }
  ]
)

tournaments << create_tournament_with_divisions(
  title:         "KHON KAEN CITY LEAGUE",
  description:   "ฟุตบอล 7 คน รายการลีกเมืองขอนแก่น แข่งแบบพบกันหมด",
  location_name: kk_arena.name,
  city:          kk_arena.city,
  province:      kk_arena.province,
  line_id:       "kk.city.league",
  contact_phone: "081-000-2000",
  team_size:     7,
  status:        :active,
  registration_open_on: Date.today,
  registration_close_on: Date.today + 21,
  competition_date: Date.today + 28,
  organizer:     admin,
  field:         kk_arena,
  divisions: [
    { name: "U14",   entry_fee: 2200, prize_amount: 4000 },
    { name: "U18",   entry_fee: 2500, prize_amount: 5000 },
    { name: "เปิดกว้าง", entry_fee: 3000, prize_amount: 8000 }
  ]
)

tournaments << create_tournament_with_divisions(
  title:         "SUMMER FUTSAL FEST",
  description:   "ฟุตซอลฤดูร้อน สำหรับเยาวชนและประชาชนทั่วไป",
  location_name: thunder_arena.name,
  city:          thunder_arena.city,
  province:      thunder_arena.province,
  line_id:       "summer.futsal",
  contact_phone: "081-000-3000",
  team_size:     5,
  status:        :active,
  registration_open_on: Date.today,
  registration_close_on: Date.today + 10,
  competition_date: Date.today + 17,
  organizer:     admin,
  field:         thunder_arena,
  divisions: [
    { name: "U10",   entry_fee: 1200, prize_amount: 2500 },
    { name: "U12",   entry_fee: 1300, prize_amount: 2800 },
    { name: "U16",   entry_fee: 1500, prize_amount: 3500 }
  ]
)

# เพิ่มทัวร์นาเมนต์ในขอนแก่นให้ครบ 5 รายการ

tournaments << create_tournament_with_divisions(
  title:         "KK NIGHT CUP",
  description:   "ฟุตบอลกลางคืนไฟสว่าง แข่งแบบน็อคเอาท์",
  location_name: kk_arena.name,
  city:          kk_arena.city,
  province:      kk_arena.province,
  line_id:       "kk.night.cup",
  contact_phone: "081-000-4000",
  team_size:     7,
  status:        :active,
  registration_open_on: Date.today,
  registration_close_on: Date.today + 7,
  competition_date: Date.today + 14,
  organizer:     admin,
  field:         kk_arena,
  divisions: [
    { name: "U13",  entry_fee: 1600, prize_amount: 3000 },
    { name: "U15",  entry_fee: 1700, prize_amount: 3500 }
  ]
)

tournaments << create_tournament_with_divisions(
  title:         "ISAN LEGENDS CUP",
  description:   "ฟุตบอลรุ่นใหญ่วัย 35+ และ 40+",
  location_name: thunder_arena.name,
  city:          thunder_arena.city,
  province:      thunder_arena.province,
  line_id:       "isan.legends",
  contact_phone: "081-000-5000",
  team_size:     7,
  status:        :active,
  registration_open_on: Date.today,
  registration_close_on: Date.today + 10,
  competition_date: Date.today + 18,
  organizer:     admin,
  field:         thunder_arena,
  divisions: [
    { name: "35+", entry_fee: 1800, prize_amount: 5000 },
    { name: "40+", entry_fee: 1700, prize_amount: 4500 }
  ]
)

# ทัวร์นาเมนต์จังหวัดกาฬสินธุ์ 3 รายการ

tournaments << create_tournament_with_divisions(
  title:         "KALASIN STREET CUP",
  description:   "ฟุตบอล 7 คน สไตล์ถนน ในเมืองกาฬสินธุ์",
  location_name: kalasin_arena.name,
  city:          kalasin_arena.city,
  province:      kalasin_arena.province,
  line_id:       "kalasin.street",
  contact_phone: "081-000-6000",
  team_size:     7,
  status:        :active,
  registration_open_on: Date.today,
  registration_close_on: Date.today + 10,
  competition_date: Date.today + 20,
  organizer:     admin,
  field:         kalasin_arena,
  divisions: [
    { name: "U12",        entry_fee: 1500, prize_amount: 3000 },
    { name: "ประชาชนทั่วไป", entry_fee: 1900, prize_amount: 5500 }
  ]
)

tournaments << create_tournament_with_divisions(
  title:         "KALASIN RAINY CUP",
  description:   "ดวลแข้งหน้าฝน พื้นสนามเปียกมันส์ ๆ",
  location_name: kalasin_arena.name,
  city:          kalasin_arena.city,
  province:      kalasin_arena.province,
  line_id:       "kalasin.rainy",
  contact_phone: "081-000-7000",
  team_size:     7,
  status:        :active,
  registration_open_on: Date.today,
  registration_close_on: Date.today + 5,
  competition_date: Date.today + 12,
  organizer:     admin,
  field:         kalasin_arena,
  divisions: [
    { name: "U16",  entry_fee: 1600, prize_amount: 3200 },
    { name: "เปิดกว้าง", entry_fee: 2100, prize_amount: 6000 }
  ]
)

tournaments << create_tournament_with_divisions(
  title:         "KALASIN VETERAN CUP",
  description:   "ฟุตบอลรุ่นพี่ 30+ และ 40+ ในกาฬสินธุ์",
  location_name: kalasin_arena.name,
  city:          kalasin_arena.city,
  province:      kalasin_arena.province,
  line_id:       "kalasin.veteran",
  contact_phone: "081-000-8000",
  team_size:     7,
  status:        :active,
  registration_open_on: Date.today,
  registration_close_on: Date.today + 12,
  competition_date: Date.today + 25,
  organizer:     admin,
  field:         kalasin_arena,
  divisions: [
    { name: "30+", entry_fee: 1700, prize_amount: 4000 },
    { name: "40+", entry_fee: 1700, prize_amount: 4500 }
  ]
)

# ทัวร์นาเมนต์จังหวัดมหาสารคาม 2 รายการ

tournaments << create_tournament_with_divisions(
  title:         "SRK UNIVERSITY CUP",
  description:   "ฟุตบอลมหาลัย / เยาวชนในมหาสารคาม",
  location_name: srk_arena.name,
  city:          srk_arena.city,
  province:      srk_arena.province,
  line_id:       "srk.university",
  contact_phone: "081-000-9000",
  team_size:     7,
  status:        :active,
  registration_open_on: Date.today,
  registration_close_on: Date.today + 14,
  competition_date: Date.today + 30,
  organizer:     admin,
  field:         srk_arena,
  divisions: [
    { name: "U18",   entry_fee: 1800, prize_amount: 5000 },
    { name: "เปิดกว้าง", entry_fee: 2200, prize_amount: 7000 }
  ]
)

tournaments << create_tournament_with_divisions(
  title:         "SRK COMMUNITY CUP",
  description:   "ฟุตบอลชุมชนรอบมหาสารคาม",
  location_name: srk_arena.name,
  city:          srk_arena.city,
  province:      srk_arena.province,
  line_id:       "srk.community",
  contact_phone: "081-000-9100",
  team_size:     7,
  status:        :active,
  registration_open_on: Date.today,
  registration_close_on: Date.today + 10,
  competition_date: Date.today + 17,
  organizer:     admin,
  field:         srk_arena,
  divisions: [
    { name: "U15",        entry_fee: 1500, prize_amount: 3200 },
    { name: "ประชาชนทั่วไป", entry_fee: 2000, prize_amount: 6500 }
  ]
)

puts "Seeding teams..."

teams = []

teams << Team.create!(
  name:           "Rajan FC",
  contact_name:   "โค้ชราชัน",
  contact_phone:  "081-111-1111",
  city:           "Khon Kaen",
  province:       "ขอนแก่น"
)

teams << Team.create!(
  name:           "สบาย FC",
  contact_name:   "โค้ชสบาย",
  contact_phone:  "082-222-2222",
  city:           "Khon Kaen",
  province:       "ขอนแก่น"
)

teams << Team.create!(
  name:           "KKU Academy",
  contact_name:   "โค้ชมข",
  contact_phone:  "083-333-3333",
  city:           "Khon Kaen",
  province:       "ขอนแก่น"
)

3.times do |i|
  teams << Team.create!(
    name:           "Khon Kaen FC #{i + 1}",
    contact_name:   "โค้ช KK #{i + 1}",
    contact_phone:  "090-000-#{(1000 + i)}",
    city:           "Khon Kaen",
    province:       "ขอนแก่น"
  )
end

puts "Seeding registrations..."

tournaments.each_with_index do |tournament, t_idx|
  divisions = tournament.tournament_divisions.order(:position, :id).to_a
  teams.each_with_index do |team, index|
    status = case (t_idx + index) % 4
             when 0 then :interested
             when 1 then :applied
             when 2 then :confirmed
             else :paid
             end

    division_for_team = divisions.any? ? divisions[(t_idx + index) % divisions.size] : nil

    TeamRegistration.create!(
      team:                team,
      tournament:          tournament,
      tournament_division: division_for_team,
      status:              status,
      notes:               "mock registration"
    )
  end
end

puts "Seed completed."
