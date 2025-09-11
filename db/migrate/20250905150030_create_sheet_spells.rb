class CreateSheetSpells < ActiveRecord::Migration[6.0]
  def change
    create_table :sheet_known_spells do |t|
      t.bigint :sheet_klass_id, null: false
      t.bigint :spell_id,       null: false
      t.integer :gained_at_class_level
      t.string  :source
      t.timestamps
    end
    add_index :sheet_known_spells, [:sheet_klass_id, :spell_id], unique: true, name: 'idx_known_spells_unique'
    add_foreign_key :sheet_known_spells, :sheet_klasses
    add_foreign_key :sheet_known_spells, :spells

    create_table :sheet_prepared_spells do |t|
      t.bigint :sheet_id, null: false
      t.bigint :spell_id, null: false
      t.boolean :auto, default: false, null: false
      t.string  :source
      t.timestamps
    end
    add_index :sheet_prepared_spells, [:sheet_id, :spell_id], unique: true, name: 'idx_prepared_spells_unique'
    add_foreign_key :sheet_prepared_spells, :sheets
    add_foreign_key :sheet_prepared_spells, :spells
  end
end

