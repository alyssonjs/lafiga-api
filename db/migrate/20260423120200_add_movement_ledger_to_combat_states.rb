# frozen_string_literal: true

# Ledger de movimento do turno actual (pés gatos + células para undo de token).
# Persiste entre reloads e tabs; esvazia em advance_turn / set_round! / finish! / begin! (re-início).
class AddMovementLedgerToCombatStates < ActiveRecord::Migration[6.0]
  def change
    add_column :combat_states, :movement_ledger, :jsonb, null: false, default: []
  end
end
