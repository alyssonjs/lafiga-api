class CreateSpellSources < ActiveRecord::Migration[6.0]
  def change
    create_table :spell_sources do |t|
      t.string  :source_type, null: false
      t.bigint  :source_id,   null: false
      t.bigint  :spell_id,    null: false
      t.integer :min_character_level
      t.integer :min_class_level
      t.boolean :always_prepared, default: false, null: false
      t.integer :uses_per_long_rest
      t.integer :uses_per_short_rest
      t.string  :ability_override
      t.text    :notes
      t.timestamps
    end

    add_index :spell_sources, [:source_type, :source_id, :spell_id], unique: true, name: 'idx_spell_sources_unique'
    add_foreign_key :spell_sources, :spells
  end
end

