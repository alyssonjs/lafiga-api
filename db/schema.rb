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

ActiveRecord::Schema.define(version: 2025_09_11_121000) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "alignments", force: :cascade do |t|
    t.string "api_index", null: false
    t.string "name", null: false
    t.string "abbreviation"
    t.text "desc"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["api_index"], name: "index_alignments_on_api_index", unique: true
  end

  create_table "backgrounds", force: :cascade do |t|
    t.string "api_index", null: false
    t.string "name", null: false
    t.string "feature_name"
    t.text "feature_desc"
    t.text "data_json"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["api_index"], name: "index_backgrounds_on_api_index", unique: true
  end

  create_table "boards", force: :cascade do |t|
    t.string "name"
    t.binary "data"
    t.bigint "user_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["user_id"], name: "index_boards_on_user_id"
  end

  create_table "channel_memberships", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "channel_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["channel_id"], name: "index_channel_memberships_on_channel_id"
    t.index ["user_id", "channel_id"], name: "idx_channel_memberships_unique", unique: true
    t.index ["user_id"], name: "index_channel_memberships_on_user_id"
  end

  create_table "channels", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.integer "kind", default: 0, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["slug"], name: "index_channels_on_slug", unique: true
  end

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

  create_table "characters_features", force: :cascade do |t|
    t.bigint "character_id", null: false
    t.bigint "feature_id", null: false
    t.string "source"
    t.integer "level"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "source_type"
    t.bigint "source_id"
    t.integer "gained_at_level"
    t.boolean "show", default: true, null: false
    t.index ["character_id", "feature_id", "show"], name: "idx_char_features_show"
    t.index ["character_id", "feature_id"], name: "idx_char_features_unique", unique: true
    t.index ["source_type", "source_id"], name: "idx_char_features_source"
  end

  create_table "class_levels", force: :cascade do |t|
    t.bigint "klass_id", null: false
    t.integer "level"
    t.integer "prof_bonus"
    t.integer "ability_score_bonuses"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["klass_id", "level"], name: "index_class_levels_on_klass_id_and_level", unique: true
    t.index ["klass_id"], name: "index_class_levels_on_klass_id"
  end

  create_table "class_levels_features", id: false, force: :cascade do |t|
    t.bigint "class_level_id", null: false
    t.bigint "feature_id", null: false
    t.index ["class_level_id", "feature_id"], name: "index_class_levels_features_on_class_level_and_feature", unique: true
    t.index ["feature_id"], name: "index_class_levels_features_on_feature_id"
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

  create_table "feats", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.text "prerequisites"
    t.text "ability_bonuses"
    t.text "proficiency_bonuses"
    t.text "features"
    t.string "api_index"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["api_index"], name: "index_feats_on_api_index"
    t.index ["name"], name: "index_feats_on_name", unique: true
  end

  create_table "features", force: :cascade do |t|
    t.string "api_index", null: false
    t.string "name", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "category", default: 0, null: false
    t.text "description"
    t.index ["api_index"], name: "index_features_on_api_index", unique: true
  end

  create_table "features_sub_klass_levels", id: false, force: :cascade do |t|
    t.bigint "sub_klass_level_id", null: false
    t.bigint "feature_id", null: false
    t.index ["feature_id"], name: "index_features_sub_klass_levels_on_feature_id"
    t.index ["sub_klass_level_id", "feature_id"], name: "idx_subklass_levels_features_unique", unique: true
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
    t.string "api_index"
    t.integer "hit_die"
    t.string "spellcasting_ability"
    t.integer "subclass_level"
    t.index ["api_index"], name: "index_klasses_on_api_index", unique: true
  end

  create_table "messages", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.bigint "user_id", null: false
    t.text "content", null: false
    t.integer "kind", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["channel_id"], name: "index_messages_on_channel_id"
    t.index ["created_at"], name: "index_messages_on_created_at"
    t.index ["user_id"], name: "index_messages_on_user_id"
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

  create_table "schedule_characters", force: :cascade do |t|
    t.bigint "character_id", null: false
    t.bigint "schedule_id", null: false
    t.integer "status", default: 1, null: false
    t.index ["character_id"], name: "index_schedule_characters_on_character_id"
    t.index ["schedule_id"], name: "index_schedule_characters_on_schedule_id"
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

  create_table "sheet_feats", force: :cascade do |t|
    t.bigint "sheet_id", null: false
    t.bigint "feat_id", null: false
    t.integer "level_gained", null: false
    t.text "choices"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["feat_id"], name: "index_sheet_feats_on_feat_id"
    t.index ["level_gained"], name: "index_sheet_feats_on_level_gained"
    t.index ["sheet_id", "feat_id"], name: "index_sheet_feats_on_sheet_id_and_feat_id", unique: true
    t.index ["sheet_id"], name: "index_sheet_feats_on_sheet_id"
  end

  create_table "sheet_items", force: :cascade do |t|
    t.bigint "sheet_id", null: false
    t.string "item_index"
    t.string "item_name", null: false
    t.string "category"
    t.integer "quantity", default: 1, null: false
    t.boolean "equipped", default: false, null: false
    t.string "slot"
    t.string "source"
    t.jsonb "props_json"
    t.text "notes"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["sheet_id", "item_index"], name: "index_sheet_items_on_sheet_id_and_item_index"
    t.index ["sheet_id"], name: "index_sheet_items_on_sheet_id"
  end

  create_table "sheet_klasses", force: :cascade do |t|
    t.bigint "sheet_id", null: false
    t.bigint "klass_id", null: false
    t.bigint "sub_klass_id"
    t.integer "level", limit: 2
    t.index ["klass_id"], name: "index_sheet_klasses_on_klass_id"
    t.index ["sheet_id", "klass_id"], name: "idx_sheet_klasses_unique_sheet_klass", unique: true
    t.index ["sheet_id"], name: "index_sheet_klasses_on_sheet_id"
    t.index ["sub_klass_id"], name: "index_sheet_klasses_on_sub_klass_id"
  end

  create_table "sheet_known_spells", force: :cascade do |t|
    t.bigint "sheet_klass_id", null: false
    t.bigint "spell_id", null: false
    t.integer "gained_at_class_level"
    t.string "source"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["sheet_klass_id", "spell_id"], name: "idx_known_spells_unique", unique: true
  end

  create_table "sheet_prepared_spells", force: :cascade do |t|
    t.bigint "sheet_id", null: false
    t.bigint "spell_id", null: false
    t.boolean "auto", default: false, null: false
    t.string "source"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["sheet_id", "spell_id"], name: "idx_prepared_spells_unique", unique: true
  end

  create_table "sheets", force: :cascade do |t|
    t.bigint "character_id", null: false
    t.bigint "sub_race_id"
    t.bigint "race_id", null: false
    t.integer "str"
    t.integer "dex"
    t.integer "con"
    t.integer "int"
    t.integer "wis"
    t.integer "cha"
    t.integer "hp_max", default: 0, null: false
    t.integer "hp_current", default: 0, null: false
    t.integer "temp_hp", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "alignment_id"
    t.bigint "background_id"
    t.string "background_key"
    t.integer "current_level", default: 1, null: false
    t.jsonb "race_choices", default: {}, null: false
    t.jsonb "class_choices", default: {}, null: false
    t.jsonb "race_summary", default: {}, null: false
    t.jsonb "class_summary", default: {}, null: false
    t.jsonb "background_summary", default: {}, null: false
    t.jsonb "features_by_level", default: {}, null: false
    t.jsonb "race_bonuses_applied", default: {}, null: false
    t.index ["alignment_id"], name: "index_sheets_on_alignment_id"
    t.index ["background_id"], name: "index_sheets_on_background_id"
    t.index ["background_key"], name: "index_sheets_on_background_key"
    t.index ["background_summary"], name: "index_sheets_on_background_summary", using: :gin
    t.index ["character_id"], name: "idx_sheets_unique_character", unique: true
    t.index ["character_id"], name: "index_sheets_on_character_id"
    t.index ["class_choices"], name: "index_sheets_on_class_choices", using: :gin
    t.index ["class_summary"], name: "index_sheets_on_class_summary", using: :gin
    t.index ["current_level"], name: "index_sheets_on_current_level"
    t.index ["features_by_level"], name: "index_sheets_on_features_by_level", using: :gin
    t.index ["race_bonuses_applied"], name: "index_sheets_on_race_bonuses_applied", using: :gin
    t.index ["race_choices"], name: "index_sheets_on_race_choices", using: :gin
    t.index ["race_id"], name: "index_sheets_on_race_id"
    t.index ["race_summary"], name: "index_sheets_on_race_summary", using: :gin
    t.index ["sub_race_id"], name: "index_sheets_on_sub_race_id"
  end

  create_table "spell_sources", force: :cascade do |t|
    t.string "source_type", null: false
    t.bigint "source_id", null: false
    t.bigint "spell_id", null: false
    t.integer "min_character_level"
    t.integer "min_class_level"
    t.boolean "always_prepared", default: false, null: false
    t.integer "uses_per_long_rest"
    t.integer "uses_per_short_rest"
    t.string "ability_override"
    t.text "notes"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["source_type", "source_id", "spell_id"], name: "idx_spell_sources_unique", unique: true
  end

  create_table "spellcastings", force: :cascade do |t|
    t.bigint "class_level_id", null: false
    t.integer "level"
    t.integer "cantrips_known"
    t.integer "spells_known"
    t.text "spell_slots"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "pact_slot_level"
    t.text "pact_slots"
    t.index ["class_level_id"], name: "index_spellcastings_on_class_level_id"
  end

  create_table "spells", force: :cascade do |t|
    t.string "api_index", null: false
    t.string "name", null: false
    t.integer "level"
    t.string "school"
    t.string "range"
    t.text "components"
    t.text "material"
    t.boolean "ritual"
    t.string "duration"
    t.boolean "concentration"
    t.string "casting_time"
    t.text "desc"
    t.text "higher_level"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["api_index"], name: "index_spells_on_api_index", unique: true
  end

  create_table "sub_klass_levels", force: :cascade do |t|
    t.bigint "sub_klass_id", null: false
    t.integer "level", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["sub_klass_id", "level"], name: "index_sub_klass_levels_on_sub_klass_id_and_level", unique: true
    t.index ["sub_klass_id"], name: "index_sub_klass_levels_on_sub_klass_id"
  end

  create_table "sub_klasses", force: :cascade do |t|
    t.string "name"
    t.bigint "klass_id", null: false
    t.string "api_index"
    t.string "subclass_flavor"
    t.text "description"
    t.text "levels_json"
    t.index ["api_index"], name: "index_sub_klasses_on_api_index", unique: true
    t.index ["klass_id"], name: "index_sub_klasses_on_klass_id"
  end

  create_table "sub_races", force: :cascade do |t|
    t.string "name"
    t.bigint "race_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["race_id"], name: "index_sub_races_on_race_id"
  end

  create_table "traits", force: :cascade do |t|
    t.string "api_index", null: false
    t.string "name", null: false
    t.text "description"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["api_index"], name: "index_traits_on_api_index", unique: true
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

  add_foreign_key "boards", "users"
  add_foreign_key "channel_memberships", "channels"
  add_foreign_key "channel_memberships", "users"
  add_foreign_key "characters", "groups"
  add_foreign_key "characters", "users"
  add_foreign_key "characters_features", "characters"
  add_foreign_key "characters_features", "features"
  add_foreign_key "class_levels", "klasses"
  add_foreign_key "messages", "channels"
  add_foreign_key "messages", "users"
  add_foreign_key "schedule_characters", "characters"
  add_foreign_key "schedule_characters", "schedules"
  add_foreign_key "schedules", "date_dimensions"
  add_foreign_key "schedules", "groups"
  add_foreign_key "sheet_feats", "feats"
  add_foreign_key "sheet_feats", "sheets"
  add_foreign_key "sheet_items", "sheets"
  add_foreign_key "sheet_klasses", "klasses"
  add_foreign_key "sheet_klasses", "sheets"
  add_foreign_key "sheet_klasses", "sub_klasses"
  add_foreign_key "sheet_known_spells", "sheet_klasses"
  add_foreign_key "sheet_known_spells", "spells"
  add_foreign_key "sheet_prepared_spells", "sheets"
  add_foreign_key "sheet_prepared_spells", "spells"
  add_foreign_key "sheets", "characters"
  add_foreign_key "sheets", "races"
  add_foreign_key "sheets", "sub_races"
  add_foreign_key "spell_sources", "spells"
  add_foreign_key "spellcastings", "class_levels"
  add_foreign_key "sub_klass_levels", "sub_klasses"
  add_foreign_key "sub_klasses", "klasses"
  add_foreign_key "sub_races", "races"
end
