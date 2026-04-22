# frozen_string_literal: true

class CombatCombatantsInitiativeNullableAndTieBreakDex < ActiveRecord::Migration[6.0]
  def change
    change_column_null :combat_combatants, :initiative, true
    change_column_default :combat_combatants, :initiative, from: 0, to: nil

    add_column :combat_combatants, :tie_break_dex, :integer, null: false, default: 10
  end
end
