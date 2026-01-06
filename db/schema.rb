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

ActiveRecord::Schema[7.2].define(version: 2026_01_06_112000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "admin_message_comments", force: :cascade do |t|
    t.bigint "admin_message_id", null: false
    t.bigint "user_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_message_id"], name: "index_admin_message_comments_on_admin_message_id"
    t.index ["user_id"], name: "index_admin_message_comments_on_user_id"
  end

  create_table "admin_messages", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "tournament_id"
    t.string "subject", null: false
    t.text "body", null: false
    t.integer "status", default: 0, null: false
    t.string "message_type"
    t.text "admin_reply"
    t.datetime "replied_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tournament_id"], name: "index_admin_messages_on_tournament_id"
    t.index ["user_id"], name: "index_admin_messages_on_user_id"
  end

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
    t.bigint "tournament_division_id"
    t.index ["team_id"], name: "index_team_registrations_on_team_id"
    t.index ["tournament_division_id"], name: "index_team_registrations_on_tournament_division_id"
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
    t.string "line_id"
  end

  create_table "tournament_divisions", force: :cascade do |t|
    t.bigint "tournament_id", null: false
    t.string "name", null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "entry_fee"
    t.integer "prize_amount"
    t.index ["tournament_id"], name: "index_tournament_divisions_on_tournament_id"
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
    t.string "line_id"
    t.string "contact_phone"
    t.date "competition_date"
    t.date "registration_open_on"
    t.date "registration_close_on"
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

  add_foreign_key "admin_message_comments", "admin_messages"
  add_foreign_key "admin_message_comments", "users"
  add_foreign_key "admin_messages", "tournaments"
  add_foreign_key "admin_messages", "users"
  add_foreign_key "fields", "users"
  add_foreign_key "team_registrations", "teams"
  add_foreign_key "team_registrations", "tournament_divisions"
  add_foreign_key "tournament_divisions", "tournaments"
  add_foreign_key "tournaments", "users", column: "organizer_id"
end
