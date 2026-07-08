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

ActiveRecord::Schema.define(version: 2026_07_08_091300) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.bigint "byte_size", null: false
    t.string "checksum", null: false
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

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
    t.jsonb "rules", default: {}, null: false
    t.string "parent_api_index"
    t.boolean "published", default: true, null: false
    t.index ["api_index"], name: "index_backgrounds_on_api_index", unique: true
    t.index ["parent_api_index"], name: "index_backgrounds_on_parent_api_index"
    t.index ["published"], name: "index_backgrounds_on_published"
  end

  create_table "battle_maps", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "group_id"
    t.string "name", null: false
    t.integer "width", null: false
    t.integer "height", null: false
    t.integer "cell_size_px", default: 32, null: false
    t.jsonb "cells", default: [], null: false
    t.jsonb "tokens", default: [], null: false
    t.jsonb "fog"
    t.text "background_image_url"
    t.float "grid_opacity", default: 1.0
    t.integer "schema_version", default: 1, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.jsonb "walls", default: [], null: false
    t.jsonb "measurements", default: [], null: false
    t.jsonb "drawings", default: [], null: false
    t.jsonb "player_permissions", default: {"pencil"=>false, "measure"=>true}, null: false
    t.float "background_image_offset_x", default: 0.0, null: false
    t.float "background_image_offset_y", default: 0.0, null: false
    t.string "distance_display_unit", default: "m", null: false
    t.decimal "cell_world_ft", precision: 6, scale: 2, default: "5.0", null: false
    t.jsonb "aoe_placements", default: [], null: false
    t.string "fog_mode", default: "hidden_cells", null: false
    t.integer "background_image_pixel_width"
    t.integer "background_image_pixel_height"
    t.jsonb "layers", default: [], null: false
    t.jsonb "terrain_layers", default: [], null: false
    t.jsonb "stamps", default: [], null: false
    t.jsonb "paths", default: [], null: false
    t.jsonb "map_effects", default: {}, null: false
    t.string "map_kind", default: "battle", null: false
    t.index ["group_id", "updated_at"], name: "index_battle_maps_on_group_id_and_updated_at"
    t.index ["group_id"], name: "index_battle_maps_on_group_id"
    t.index ["user_id", "updated_at"], name: "index_battle_maps_on_user_id_and_updated_at"
    t.index ["user_id"], name: "index_battle_maps_on_user_id"
  end

  create_table "campaign_notes", force: :cascade do |t|
    t.bigint "group_id", null: false
    t.bigint "schedule_id"
    t.bigint "user_id", null: false
    t.string "title", default: "", null: false
    t.text "body", default: "", null: false
    t.integer "kind", default: 0, null: false
    t.integer "visibility", default: 0, null: false
    t.boolean "pinned", default: false, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["group_id", "kind"], name: "index_campaign_notes_on_group_id_and_kind"
    t.index ["group_id", "pinned"], name: "index_campaign_notes_on_group_id_and_pinned"
    t.index ["group_id", "updated_at"], name: "index_campaign_notes_on_group_id_and_updated_at"
    t.index ["group_id"], name: "index_campaign_notes_on_group_id"
    t.index ["schedule_id"], name: "index_campaign_notes_on_schedule_id"
    t.index ["user_id"], name: "index_campaign_notes_on_user_id"
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

  create_table "character_dm_level_unlocks", force: :cascade do |t|
    t.bigint "character_id", null: false
    t.bigint "unlocked_by_user_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["character_id"], name: "index_character_dm_level_unlocks_on_character_id", unique: true
    t.index ["unlocked_by_user_id"], name: "index_character_dm_level_unlocks_on_unlocked_by_user_id"
  end

  create_table "characters", force: :cascade do |t|
    t.string "name"
    t.text "background"
    t.bigint "user_id", null: false
    t.bigint "group_id"
    t.integer "status", default: 0, null: false
    t.integer "current_step"
    t.jsonb "draft_data", default: {}
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.text "dm_notes"
    t.index ["group_id"], name: "index_characters_on_group_id"
    t.index ["user_id"], name: "index_characters_on_user_id"
  end

  create_table "characters_features", force: :cascade do |t|
    t.bigint "character_id", null: false
    t.bigint "feature_id", null: false
    t.string "source"
    t.integer "level"
    t.string "source_type"
    t.bigint "source_id"
    t.integer "gained_at_level"
    t.boolean "show", default: true, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["character_id", "feature_id", "show"], name: "idx_char_features_show"
    t.index ["character_id", "feature_id"], name: "idx_char_features_unique", unique: true
    t.index ["character_id"], name: "index_characters_features_on_character_id"
    t.index ["feature_id"], name: "index_characters_features_on_feature_id"
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

  create_table "combat_combatants", force: :cascade do |t|
    t.bigint "combat_state_id", null: false
    t.string "combatable_type", null: false
    t.bigint "combatable_id", null: false
    t.string "name", null: false
    t.integer "initiative"
    t.integer "initiative_bonus", default: 0, null: false
    t.integer "position", null: false
    t.integer "hp_current", default: 0, null: false
    t.integer "hp_max", default: 0, null: false
    t.integer "ac", default: 10, null: false
    t.integer "temp_hp", default: 0, null: false
    t.boolean "is_delayed", default: false, null: false
    t.boolean "is_concentrating", default: false, null: false
    t.string "concentration_spell"
    t.boolean "is_stabilized", default: false, null: false
    t.boolean "is_dead", default: false, null: false
    t.jsonb "conditions", default: [], null: false
    t.jsonb "actions_used", default: {"action"=>false, "movement"=>false, "reaction"=>false, "bonus_action"=>false}, null: false
    t.jsonb "death_saves", default: {"failures"=>0, "successes"=>0}, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "tie_break_dex", default: 10, null: false
    t.index ["combat_state_id", "position"], name: "index_combat_combatants_on_state_and_position", unique: true
    t.index ["combat_state_id"], name: "index_combat_combatants_on_combat_state_id"
    t.index ["combatable_type", "combatable_id"], name: "index_combat_combatants_on_combatable"
    t.index ["combatable_type", "combatable_id"], name: "index_combat_combatants_on_combatable_type_and_combatable_id"
  end

  create_table "combat_npcs", force: :cascade do |t|
    t.bigint "schedule_id", null: false
    t.string "name", null: false
    t.integer "hp_current", default: 0, null: false
    t.integer "hp_max", default: 0, null: false
    t.integer "ac", default: 10, null: false
    t.integer "base_ac"
    t.integer "speed"
    t.string "cr"
    t.integer "proficiency_bonus"
    t.string "monster_id"
    t.jsonb "stats", default: {}, null: false
    t.jsonb "saving_throws", default: {}, null: false
    t.jsonb "skills", default: {}, null: false
    t.jsonb "attacks", default: [], null: false
    t.jsonb "equipment", default: {}, null: false
    t.text "notes", default: "", null: false
    t.datetime "defeated_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.jsonb "resistances", default: [], null: false
    t.jsonb "damage_immunities", default: [], null: false
    t.jsonb "damage_vulnerabilities", default: [], null: false
    t.jsonb "condition_immunities", default: [], null: false
    t.jsonb "legendary_actions", default: [], null: false
    t.jsonb "lair_actions", default: [], null: false
    t.index ["schedule_id"], name: "index_combat_npcs_on_schedule_id"
    t.index ["schedule_id"], name: "index_combat_npcs_on_schedule_id_alive", where: "(defeated_at IS NULL)"
  end

  create_table "combat_states", force: :cascade do |t|
    t.bigint "schedule_id", null: false
    t.boolean "active", default: false, null: false
    t.integer "round", default: 0, null: false
    t.integer "current_turn_index", default: 0, null: false
    t.datetime "started_at"
    t.datetime "ended_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.jsonb "movement_ledger", default: [], null: false
    t.index ["schedule_id"], name: "index_combat_states_on_schedule_id", unique: true
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
    t.index ["date"], name: "idx_date_dimensions_unique_date", unique: true
  end

  create_table "diary_entries", force: :cascade do |t|
    t.bigint "character_id", null: false
    t.bigint "schedule_id"
    t.string "title", default: "", null: false
    t.text "content", default: "", null: false
    t.string "font_family", default: "Caveat", null: false
    t.integer "font_size", default: 16, null: false
    t.string "text_color", default: "#3e2723", null: false
    t.string "page_color", default: "#f5e6d3", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["character_id", "updated_at"], name: "index_diary_entries_on_character_id_and_updated_at"
    t.index ["character_id"], name: "index_diary_entries_on_character_id"
    t.index ["schedule_id"], name: "index_diary_entries_on_schedule_id"
  end

  create_table "feats", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.text "prerequisites"
    t.text "ability_bonuses"
    t.text "proficiency_bonuses"
    t.text "features"
    t.string "api_index"
    t.json "special_rules"
    t.json "cantrips"
    t.json "spells"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["api_index"], name: "index_feats_on_api_index"
    t.index ["name"], name: "index_feats_on_name", unique: true
  end

  create_table "features", force: :cascade do |t|
    t.string "api_index", null: false
    t.string "name", null: false
    t.integer "category", default: 0, null: false
    t.text "description"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.boolean "dm_customized", default: false, null: false
    t.index ["api_index"], name: "index_features_on_api_index", unique: true
    t.index ["dm_customized"], name: "index_features_on_dm_customized"
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
    t.string "cover_image_url"
    t.bigint "dm_user_id"
    t.index ["dm_user_id"], name: "index_groups_on_dm_user_id"
    t.index ["dm_user_id"], name: "index_groups_on_dm_user_id_not_null", where: "(dm_user_id IS NOT NULL)"
  end

  create_table "items", force: :cascade do |t|
    t.string "api_index", null: false
    t.string "name", null: false
    t.string "kind", null: false
    t.string "category"
    t.decimal "value_gp", precision: 10, scale: 2
    t.decimal "weight_kg", precision: 8, scale: 2
    t.string "rarity"
    t.boolean "requires_attunement", default: false, null: false
    t.string "attunement_note"
    t.string "sub_category"
    t.boolean "cursed", default: false
    t.text "curse_text"
    t.integer "charges"
    t.string "recharge"
    t.string "source"
    t.text "description"
    t.text "tags", default: [], array: true
    t.jsonb "props", default: {}
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.boolean "is_wondrous", default: false, null: false
    t.index ["api_index"], name: "index_items_on_api_index", unique: true
    t.index ["category"], name: "index_items_on_category"
    t.index ["kind"], name: "index_items_on_kind"
    t.index ["props"], name: "index_items_on_props", using: :gin
    t.index ["rarity"], name: "index_items_on_rarity"
    t.index ["tags"], name: "index_items_on_tags", using: :gin
  end

  create_table "klasses", force: :cascade do |t|
    t.string "name"
    t.string "api_index"
    t.integer "hit_die"
    t.string "spellcasting_ability"
    t.integer "subclass_level"
    t.jsonb "rules"
    t.text "description"
    t.string "primary_ability"
    t.jsonb "saving_throws", default: []
    t.string "short_description"
    t.text "progression_table"
    t.boolean "playable", default: true, null: false
    t.index ["api_index"], name: "index_klasses_on_api_index", unique: true
    t.index ["playable"], name: "index_klasses_on_playable"
  end

  create_table "magic_items", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "rarity"
    t.string "category"
    t.string "sub_category"
    t.boolean "requires_attunement", default: false, null: false
    t.string "attunement_note"
    t.decimal "weight_kg", precision: 8, scale: 2
    t.decimal "value_gp", precision: 10, scale: 2
    t.string "source"
    t.boolean "cursed", default: false
    t.text "curse_text"
    t.integer "charges"
    t.string "recharge"
    t.jsonb "bonuses", default: {}
    t.jsonb "properties", default: {}
    t.text "description"
    t.text "tags", default: [], array: true
    t.jsonb "effects", default: []
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.boolean "is_wondrous", default: false, null: false
    t.index ["category"], name: "index_magic_items_on_category"
    t.index ["name"], name: "index_magic_items_on_name"
    t.index ["rarity"], name: "index_magic_items_on_rarity"
    t.index ["slug"], name: "index_magic_items_on_slug", unique: true
    t.index ["tags"], name: "index_magic_items_on_tags", using: :gin
  end

  create_table "map_assets", force: :cascade do |t|
    t.string "name", null: false
    t.string "kind", null: false
    t.string "category", default: "custom", null: false
    t.string "color"
    t.boolean "enabled", default: true, null: false
    t.bigint "user_id"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["kind", "enabled"], name: "index_map_assets_on_kind_and_enabled"
    t.index ["kind"], name: "index_map_assets_on_kind"
    t.index ["user_id"], name: "index_map_assets_on_user_id"
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

  create_table "monsters", force: :cascade do |t|
    t.string "slug", null: false
    t.string "name", null: false
    t.string "name_en"
    t.string "size"
    t.string "monster_type"
    t.string "alignment"
    t.string "cr", default: "0", null: false
    t.float "cr_numeric", default: 0.0, null: false
    t.integer "xp", default: 0, null: false
    t.integer "ac"
    t.integer "hp"
    t.string "source", default: "srd", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["cr_numeric"], name: "index_monsters_on_cr_numeric"
    t.index ["monster_type"], name: "index_monsters_on_monster_type"
    t.index ["name"], name: "index_monsters_on_name"
    t.index ["payload"], name: "index_monsters_on_payload", using: :gin
    t.index ["slug"], name: "index_monsters_on_slug", unique: true
    t.index ["source"], name: "index_monsters_on_source"
  end

  create_table "race_traits", force: :cascade do |t|
    t.bigint "race_id", null: false
    t.bigint "trait_id", null: false
    t.bigint "sub_race_id"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["race_id", "trait_id", "sub_race_id"], name: "idx_race_traits_unique", unique: true
    t.index ["race_id"], name: "index_race_traits_on_race_id"
    t.index ["sub_race_id"], name: "index_race_traits_on_sub_race_id"
    t.index ["trait_id"], name: "index_race_traits_on_trait_id"
  end

  create_table "races", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "api_index"
    t.boolean "playable", default: true, null: false
    t.index ["api_index"], name: "index_races_on_api_index", unique: true
    t.index ["playable"], name: "index_races_on_playable"
  end

  create_table "roles", force: :cascade do |t|
    t.string "name"
    t.string "permissions", default: [], array: true
  end

  create_table "schedule_characters", force: :cascade do |t|
    t.bigint "character_id", null: false
    t.bigint "schedule_id", null: false
    t.integer "status", default: 1, null: false
    t.index ["character_id", "schedule_id"], name: "idx_schedule_characters_unique_character_schedule", unique: true
    t.index ["character_id"], name: "index_schedule_characters_on_character_id"
    t.index ["schedule_id"], name: "index_schedule_characters_on_schedule_id"
  end

  create_table "schedules", force: :cascade do |t|
    t.integer "status", default: 1, null: false
    t.bigint "date_dimension_id", null: false
    t.bigint "group_id"
    t.string "title", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.text "description"
    t.text "summary"
    t.integer "xp_awarded", default: 0, null: false
    t.datetime "started_at"
    t.datetime "ended_at"
    t.jsonb "highlights", default: [], null: false
    t.string "scheduled_time"
    t.string "campaign_name"
    t.bigint "battle_map_id"
    t.text "dm_notes"
    t.jsonb "linked_npc_character_ids", default: [], null: false
    t.jsonb "dm_temp_npc_character_ids", default: [], null: false
    t.bigint "created_by_user_id"
    t.index ["battle_map_id"], name: "index_schedules_on_battle_map_id"
    t.index ["campaign_name"], name: "index_schedules_on_campaign_name"
    t.index ["created_by_user_id", "date_dimension_id"], name: "idx_schedules_open_per_creator_date", unique: true, where: "((created_by_user_id IS NOT NULL) AND (status = ANY (ARRAY[0, 1, 2])))"
    t.index ["created_by_user_id"], name: "index_schedules_on_created_by_user_id"
    t.index ["group_id"], name: "idx_schedules_open_per_group", unique: true, where: "((group_id IS NOT NULL) AND (status = ANY (ARRAY[0, 1, 2])))"
    t.index ["group_id"], name: "index_schedules_on_group_id"
    t.index ["highlights"], name: "index_schedules_on_highlights", using: :gin
    t.index ["status"], name: "index_schedules_on_status"
  end

  create_table "session_feed_items", force: :cascade do |t|
    t.bigint "schedule_id", null: false
    t.string "kind", null: false
    t.string "client_id", null: false
    t.string "roll_group_id"
    t.jsonb "payload", default: {}, null: false
    t.datetime "posted_at", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["schedule_id", "client_id"], name: "index_session_feed_items_on_schedule_and_client_id_uniq", unique: true
    t.index ["schedule_id", "posted_at"], name: "index_session_feed_items_on_schedule_and_posted_at_desc", order: { posted_at: :desc }
    t.index ["schedule_id", "roll_group_id"], name: "index_session_feed_items_on_schedule_and_roll_group_id", where: "(roll_group_id IS NOT NULL)"
    t.index ["schedule_id"], name: "index_session_feed_items_on_schedule_id"
  end

  create_table "session_logs", force: :cascade do |t|
    t.bigint "schedule_id", null: false
    t.integer "kind", default: 0, null: false
    t.string "actor"
    t.text "message", default: "", null: false
    t.jsonb "roll_result"
    t.datetime "posted_at", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["schedule_id", "kind"], name: "index_session_logs_on_schedule_id_and_kind"
    t.index ["schedule_id", "posted_at"], name: "index_session_logs_on_schedule_and_posted_at_desc", order: { posted_at: :desc }
    t.index ["schedule_id"], name: "index_session_logs_on_schedule_id"
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
    t.index ["sheet_id", "feat_id", "level_gained"], name: "index_sheet_feats_on_sheet_feat_level", unique: true
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
    t.bigint "item_id"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["item_id"], name: "index_sheet_items_on_item_id"
    t.index ["sheet_id", "item_index"], name: "index_sheet_items_on_sheet_id_and_item_index"
    t.index ["sheet_id"], name: "index_sheet_items_on_sheet_id"
  end

  create_table "sheet_klasses", force: :cascade do |t|
    t.bigint "sheet_id", null: false
    t.bigint "klass_id", null: false
    t.bigint "sub_klass_id"
    t.integer "level", limit: 2
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
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
    t.string "uses_per_rest"
    t.integer "uses_remaining", default: 0
    t.index ["sheet_klass_id", "spell_id"], name: "idx_known_spells_unique", unique: true
    t.index ["source"], name: "index_sheet_known_spells_on_source"
    t.index ["uses_per_rest"], name: "index_sheet_known_spells_on_uses_per_rest"
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

  create_table "sheet_runtime_states", force: :cascade do |t|
    t.bigint "sheet_id", null: false
    t.jsonb "death_saves", default: {"stable"=>false, "failures"=>0, "successes"=>0}, null: false
    t.jsonb "hit_dice_used", default: {}, null: false
    t.integer "exhaustion", default: 0, null: false
    t.jsonb "conditions", default: [], null: false
    t.jsonb "concentration"
    t.jsonb "spell_slots_used", default: {}, null: false
    t.jsonb "class_resources_used", default: {}, null: false
    t.datetime "last_short_rest_at"
    t.datetime "last_long_rest_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.jsonb "active_effects", default: [], null: false
    t.index ["sheet_id"], name: "index_sheet_runtime_states_on_sheet_id", unique: true
  end

  create_table "sheets", force: :cascade do |t|
    t.bigint "character_id", null: false
    t.bigint "sub_race_id"
    t.bigint "race_id", null: false
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
    t.jsonb "metadata", default: {}, null: false
    t.integer "str"
    t.integer "dex"
    t.integer "con"
    t.integer "int"
    t.integer "wis"
    t.integer "cha"
    t.integer "hp_max", default: 0, null: false
    t.integer "hp_current", default: 0, null: false
    t.integer "temp_hp", default: 0, null: false
    t.jsonb "avatar_customization", default: {}, null: false
    t.integer "experience_points", default: 0, null: false
    t.jsonb "coins", default: {"cp"=>0, "ep"=>0, "gp"=>0, "pp"=>0, "sp"=>0}, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.jsonb "coin_pouches", default: [], null: false
    t.index ["alignment_id"], name: "index_sheets_on_alignment_id"
    t.index ["background_id"], name: "index_sheets_on_background_id"
    t.index ["background_key"], name: "index_sheets_on_background_key"
    t.index ["background_summary"], name: "index_sheets_on_background_summary", using: :gin
    t.index ["character_id"], name: "idx_sheets_unique_character", unique: true
    t.index ["character_id"], name: "index_sheets_on_character_id"
    t.index ["class_choices"], name: "index_sheets_on_class_choices", using: :gin
    t.index ["class_summary"], name: "index_sheets_on_class_summary", using: :gin
    t.index ["current_level"], name: "index_sheets_on_current_level"
    t.index ["experience_points"], name: "index_sheets_on_experience_points"
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
    t.integer "pact_slot_level"
    t.text "pact_slots"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
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
    t.boolean "playable", default: true, null: false
    t.jsonb "terrain_spells"
    t.jsonb "bonus_spells"
    t.index ["api_index"], name: "index_sub_klasses_on_api_index"
    t.index ["klass_id", "api_index"], name: "idx_sub_klasses_unique_klass_api", unique: true
    t.index ["klass_id"], name: "index_sub_klasses_on_klass_id"
    t.index ["playable"], name: "index_sub_klasses_on_playable"
  end

  create_table "sub_races", force: :cascade do |t|
    t.string "name"
    t.bigint "race_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "api_index"
    t.boolean "playable", default: true, null: false
    t.index ["playable"], name: "index_sub_races_on_playable"
    t.index ["race_id", "api_index"], name: "index_sub_races_on_race_id_and_api_index", unique: true
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
    t.jsonb "progression_settings", default: {}, null: false
    t.datetime "password_changed_at"
    t.index ["role_id"], name: "index_users_on_role_id"
  end

  create_table "validate_jwt_tokens", force: :cascade do |t|
    t.string "token"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "weapons", force: :cascade do |t|
    t.string "api_index", null: false
    t.string "name", null: false
    t.string "category"
    t.string "range_type"
    t.integer "hands"
    t.string "damage_die"
    t.string "versatile_die"
    t.string "range"
    t.jsonb "properties", default: []
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["api_index"], name: "index_weapons_on_api_index", unique: true
    t.index ["category"], name: "index_weapons_on_category"
    t.index ["range_type"], name: "index_weapons_on_range_type"
  end

  create_table "wiki_sections", force: :cascade do |t|
    t.string "slug", null: false
    t.string "label", null: false
    t.text "description"
    t.string "icon_name", default: "BookOpen", null: false
    t.integer "position", default: 0, null: false
    t.boolean "built_in", default: false, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["built_in", "position"], name: "index_wiki_sections_on_built_in_and_position"
    t.index ["slug"], name: "index_wiki_sections_on_slug", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "battle_maps", "groups"
  add_foreign_key "battle_maps", "users"
  add_foreign_key "campaign_notes", "groups"
  add_foreign_key "campaign_notes", "schedules"
  add_foreign_key "campaign_notes", "users"
  add_foreign_key "channel_memberships", "channels"
  add_foreign_key "channel_memberships", "users"
  add_foreign_key "character_dm_level_unlocks", "characters"
  add_foreign_key "character_dm_level_unlocks", "users", column: "unlocked_by_user_id"
  add_foreign_key "characters", "groups"
  add_foreign_key "characters", "users"
  add_foreign_key "characters_features", "characters"
  add_foreign_key "characters_features", "features"
  add_foreign_key "class_levels", "klasses"
  add_foreign_key "combat_combatants", "combat_states"
  add_foreign_key "combat_npcs", "schedules"
  add_foreign_key "combat_states", "schedules"
  add_foreign_key "diary_entries", "characters"
  add_foreign_key "diary_entries", "schedules"
  add_foreign_key "groups", "users", column: "dm_user_id"
  add_foreign_key "map_assets", "users"
  add_foreign_key "messages", "channels"
  add_foreign_key "messages", "users"
  add_foreign_key "race_traits", "races"
  add_foreign_key "race_traits", "sub_races"
  add_foreign_key "race_traits", "traits"
  add_foreign_key "schedule_characters", "characters"
  add_foreign_key "schedule_characters", "schedules"
  add_foreign_key "schedules", "battle_maps"
  add_foreign_key "schedules", "date_dimensions"
  add_foreign_key "schedules", "groups"
  add_foreign_key "schedules", "users", column: "created_by_user_id"
  add_foreign_key "session_feed_items", "schedules"
  add_foreign_key "session_logs", "schedules"
  add_foreign_key "sheet_feats", "feats"
  add_foreign_key "sheet_feats", "sheets"
  add_foreign_key "sheet_items", "items"
  add_foreign_key "sheet_items", "sheets"
  add_foreign_key "sheet_klasses", "klasses"
  add_foreign_key "sheet_klasses", "sheets"
  add_foreign_key "sheet_klasses", "sub_klasses"
  add_foreign_key "sheet_known_spells", "sheet_klasses"
  add_foreign_key "sheet_known_spells", "spells"
  add_foreign_key "sheet_prepared_spells", "sheets"
  add_foreign_key "sheet_prepared_spells", "spells"
  add_foreign_key "sheet_runtime_states", "sheets"
  add_foreign_key "sheets", "characters"
  add_foreign_key "sheets", "races"
  add_foreign_key "sheets", "sub_races"
  add_foreign_key "spell_sources", "spells"
  add_foreign_key "spellcastings", "class_levels"
  add_foreign_key "sub_klass_levels", "sub_klasses"
  add_foreign_key "sub_klasses", "klasses"
  add_foreign_key "sub_races", "races"
end
