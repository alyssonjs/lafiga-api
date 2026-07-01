class AddTurnStateToCombatCombatants < ActiveRecord::Migration[6.0]
  def change
    add_column :combat_combatants, :turn_state, :jsonb, default: {}, null: false
  end
end
