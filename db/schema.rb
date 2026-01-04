# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_01_04_070000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "fields", force: :cascade do |t|
    t.string "name"
    t.string "address"
    t.string "city"
    t.string "province"
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.integer "field_type"
    t.integer "price_per_hour"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_fields_on_user_id"
  end

  create_table "team_registrations", force: :cascade do |t|
    t.integer "status"
    t.text "notes"
    t.bigint "team_id", null: false
    t.bigint "tournament_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id"], name: "index_team_registrations_on_team_id"
    t.index ["tournament_id"], name: "index_team_registrations_on_tournament_id"
  end

  create_table "teams", force: :cascade do |t|
    t.string "name"
    t.string "contact_name"
    t.string "contact_phone"
    t.string "city"
    t.string "province"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "tournaments", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.string "location_name"
    t.string "city"
    t.string "province"
    t.string "age_category"
    t.integer "team_size"
    t.integer "entry_fee"
    t.integer "prize_amount"
    t.integer "status"
    t.bigint "organizer_id", null: false
    t.bigint "field_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["field_id"], name: "index_tournaments_on_field_id"
    t.index ["organizer_id"], name: "index_tournaments_on_organizer_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.string "phone"
    t.string "provider"
    t.string "uid"
    t.integer "role"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "fields", "users"
  add_foreign_key "team_registrations", "teams"
  add_foreign_key "tournaments", "users", column: "organizer_id"
end
