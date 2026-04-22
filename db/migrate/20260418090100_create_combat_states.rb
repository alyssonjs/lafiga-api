class CreateCombatStates < ActiveRecord::Migration[6.0]
  # Estado global de combate de uma sessão (Schedule). Singleton 1:1 — por isso
  # o índice único em `schedule_id`. Quando o DM clica "Iniciar Combate" pela
  # primeira vez, o registro é criado; reinícios futuros apenas atualizam os
  # campos (`started_at` é preservado em encerramento, `ended_at` marca o fim).
  #
  # `current_turn_index` referencia a posição de `combat_combatants.position`
  # do combatente cujo turno está ativo. Quando o combate não está ativo
  # (`active=false`), o valor é apenas histórico.
  #
  # Mantemos o registro mesmo após o combate terminar (em vez de deletar) para
  # alimentar futuros recaps e analytics. O DM pode iniciar um novo combate
  # na mesma sessão e o serviço cuida de resetar `round`, limpar combatentes
  # e atualizar `started_at`.
  def change
    create_table :combat_states do |t|
      t.references :schedule, null: false, foreign_key: true, index: { unique: true }

      t.boolean  :active,             default: false, null: false
      t.integer  :round,              default: 0,     null: false
      t.integer  :current_turn_index, default: 0,     null: false
      t.datetime :started_at
      t.datetime :ended_at

      t.timestamps
    end
  end
end
