class CreateSheetRuntimeStates < ActiveRecord::Migration[6.0]
  # Estado mutável (runtime) de uma ficha. 1:1 com `sheets`.
  #
  # Por que tabela separada e não `sheets.metadata`?
  # - `sheets.metadata` carrega class_choices/per_level/race_summary que são
  #   versionados e reconciliados em level-up. Runtime muda dezenas de vezes
  #   por sessão e não deve invalidar cache do build.
  # - PATCH atômico/leve: endpoint dedicado toca uma row pequena, sem reentrar
  #   em validações de build (process_sheet_params).
  # - HP fica em `sheets` (`hp_current`/`hp_max`/`temp_hp`) onde já está e já
  #   tem PATCH funcionando — runtime cobre tudo MENOS HP.
  #
  # Campos JSONB (defaults safe-by-construction):
  # - death_saves: { successes: 0..3, failures: 0..3, stable: bool }
  # - hit_dice_used: { "d6": int, "d8": int, "d10": int, "d12": int }
  # - conditions: ["fadigado", "amedrontado", ...]
  # - concentration: { spell:, level:, ends_at: } | null
  # - spell_slots_used: { "1": int, "2": int, ..., "pact": int, "arcane_recovery": int }
  # - class_resources_used: { rage: int, ki: int, action_surge: int, ... }
  def change
    create_table :sheet_runtime_states do |t|
      t.references :sheet, null: false, foreign_key: true, index: { unique: true }

      t.jsonb :death_saves,           default: { 'successes' => 0, 'failures' => 0, 'stable' => false }, null: false
      t.jsonb :hit_dice_used,         default: {}, null: false
      t.integer :exhaustion,          default: 0,  null: false
      t.jsonb :conditions,            default: [], null: false
      t.jsonb :concentration

      t.jsonb :spell_slots_used,      default: {}, null: false
      t.jsonb :class_resources_used,  default: {}, null: false

      t.datetime :last_short_rest_at
      t.datetime :last_long_rest_at

      t.timestamps
    end
  end
end
