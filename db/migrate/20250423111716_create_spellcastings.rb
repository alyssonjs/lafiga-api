class CreateSpellcastings < ActiveRecord::Migration[6.0]
  def change
    create_table :spellcastings do |t|
      t.references :class_level, null: false, foreign_key: true
      t.integer :level
      t.integer :cantrips_known
      t.integer :spells_known
      t.text :spell_slots
      t.integer :pact_slot_level
      t.text :pact_slots

      t.timestamps
    end
  end
end
