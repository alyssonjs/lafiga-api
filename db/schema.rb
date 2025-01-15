# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `rails
# db:schema:load`. When creating a new database, `rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2025_01_15_010804) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "characters", force: :cascade do |t|
    t.string "name"
    t.text "background"
    t.bigint "user_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.bigint "group_id"
    t.index ["group_id"], name: "index_characters_on_group_id"
    t.index ["user_id"], name: "index_characters_on_user_id"
  end

  create_table "date_dimensions", force: :cascade do |t|
    t.date "date"
    t.integer "year"
    t.integer "month"
    t.integer "day"
    t.integer "day_of_week"
    t.string "day_name"
    t.boolean "is_weekend"
    t.boolean "available"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "groups", force: :cascade do |t|
    t.string "name"
    t.integer "season", default: 0
    t.integer "day", null: false
    t.integer "year"
    t.text "description"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "klasses", force: :cascade do |t|
    t.string "name"
  end

  create_table "races", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "roles", force: :cascade do |t|
    t.string "name"
    t.string "permissions", default: [], array: true
  end

  create_table "schedules", force: :cascade do |t|
    t.integer "status", default: 1, null: false
    t.bigint "date_dimension_id", null: false
    t.string "title", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.bigint "group_id"
    t.index ["date_dimension_id"], name: "index_schedules_on_date_dimension_id"
    t.index ["group_id"], name: "index_schedules_on_group_id"
  end

  create_table "sub_klasses", force: :cascade do |t|
    t.string "name"
    t.bigint "klass_id", null: false
    t.index ["klass_id"], name: "index_sub_klasses_on_klass_id"
  end

  create_table "sub_races", force: :cascade do |t|
    t.string "name"
    t.bigint "race_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["race_id"], name: "index_sub_races_on_race_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name"
    t.string "username"
    t.string "email"
    t.string "phone"
    t.string "password_digest"
    t.bigint "role_id"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["role_id"], name: "index_users_on_role_id"
  end

  create_table "validate_jwt_tokens", force: :cascade do |t|
    t.string "token"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  add_foreign_key "characters", "groups"
  add_foreign_key "characters", "users"
  add_foreign_key "schedules", "date_dimensions"
  add_foreign_key "schedules", "groups"
  add_foreign_key "sub_klasses", "klasses"
  add_foreign_key "sub_races", "races"
end
