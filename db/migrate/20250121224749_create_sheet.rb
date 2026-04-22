class CreateSheet < ActiveRecord::Migration[6.0]
  def change
    create_table :sheets do |t|
      t.references :character, null: false, foreign_key: true
      t.references :sub_race, foreign_key: true
      t.references :race, null: false, foreign_key: true
      t.references :alignment, index: true
      t.references :background, index: true
      t.string :background_key
      t.integer :current_level, default: 1, null: false
      t.jsonb :race_choices, default: {}, null: false
      t.jsonb :class_choices, default: {}, null: false
      t.jsonb :race_summary, default: {}, null: false
      t.jsonb :class_summary, default: {}, null: false
      t.jsonb :background_summary, default: {}, null: false
      t.jsonb :features_by_level, default: {}, null: false
      t.jsonb :race_bonuses_applied, default: {}, null: false
      t.jsonb :metadata, default: {}, null: false
      t.integer :str
      t.integer :dex
      t.integer :con
      t.integer :int
      t.integer :wis
      t.integer :cha
      t.integer :hp_max, default: 0, null: false
      t.integer :hp_current, default: 0, null: false
      t.integer :temp_hp, default: 0, null: false
    end

    add_index :sheets, :character_id, unique: true, name: 'idx_sheets_unique_character'
    add_index :sheets, :background_key
    add_index :sheets, :current_level
    add_index :sheets, :race_choices, using: :gin
    add_index :sheets, :class_choices, using: :gin
    add_index :sheets, :race_summary, using: :gin
    add_index :sheets, :class_summary, using: :gin
    add_index :sheets, :background_summary, using: :gin
    add_index :sheets, :features_by_level, using: :gin
    add_index :sheets, :race_bonuses_applied, using: :gin
  end
end
