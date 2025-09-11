class AddPactMagicToSpellcastings < ActiveRecord::Migration[6.0]
  def change
    add_column :spellcastings, :pact_slot_level, :integer
    add_column :spellcastings, :pact_slots, :text
  end
end

