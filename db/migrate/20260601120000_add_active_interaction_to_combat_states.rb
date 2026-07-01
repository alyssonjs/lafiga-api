# frozen_string_literal: true

# Interação de combate activa (disputa Empurrar/Agarrar, salvaguarda, janela de
# reação) — Fase 1 do mecanismo genérico de interação. Vive no estado de combate
# (1:1 com Schedule), ao lado de `movement_ledger`, e é sincronizada via
# ActionCable no mesmo `state_changed` para que o cliente do DEFENSOR receba o
# prompt em tempo real.
#
# Shape livre (jsonb), seguindo o design `_HOTBAR-disputa-reacoes-design.md`:
#   { id, kind, phase, source_id, target_ids[], pending_responders[],
#     contest{ attacker_skill, defender_skill_options, attacker_roll,
#              defender_roll, outcome }, label }
#
# Nullable: `null` significa "sem interação pendente" (estado de repouso).
# Idempotente: só adiciona a coluna se ainda não existir.
class AddActiveInteractionToCombatStates < ActiveRecord::Migration[6.0]
  def change
    unless column_exists?(:combat_states, :active_interaction)
      add_column :combat_states, :active_interaction, :jsonb, null: true
    end
  end
end
