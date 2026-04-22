class CreateCombatCombatants < ActiveRecord::Migration[6.0]
  # Linhas do tracker de iniciativa. Cada combatente referencia EITHER um
  # `Character` (PC) OR um `CombatNpc` (NPC) via associação polimórfica
  # `combatable`. Isso evita duas tabelas paralelas (PC-tracker + NPC-tracker)
  # e mantém a turn order única, ordenada por `position` ASC.
  #
  # Por que duplicar `name`/`hp_current`/`hp_max`/`ac` em vez de sempre buscar
  # da Sheet/CombatNpc?
  # - HP de combate diverge da HP "fora de combate". Durante a batalha o front
  #   precisa atualizar HP em alta frequência sem mexer no Sheet do PC. Ao fim
  #   do combate, o serviço de encerramento sincroniza HP do combatente PC de
  #   volta para a Sheet (cura/dano persiste, mas o tracking detalhado fica
  #   isolado).
  # - `name` é cacheado para o caso de o NPC ser renomeado mid-combate sem
  #   propagar pra log histórico. Também simplifica o broadcast (uma única
  #   linha contém tudo que o tracker precisa).
  # - `ac` espelha o valor do momento (ajustável via spells/effects no combate).
  #
  # Campos JSONB:
  # - `conditions`: [{ id: 'poisoned', turns_left: 3 }, { id: 'blinded', turns_left: null }]
  #   `turns_left = null` significa indefinido (até remoção manual).
  # - `actions_used`: { action: false, bonus_action: false, movement: false, reaction: false }
  #   Resetado a cada turno do combatente.
  # - `death_saves`: { successes: 0, failures: 0 } (0..3 cada)
  #
  # `position` é a ordem visual do tracker (ASC). Empates de iniciativa são
  # quebrados por `position` (não por `initiative` ASC), o que dá ao DM
  # controle manual de "quem age primeiro" via reordenação.
  def change
    create_table :combat_combatants do |t|
      t.references :combat_state, null: false, foreign_key: true
      t.references :combatable, polymorphic: true, null: false

      t.string  :name,              null: false
      t.integer :initiative,        default: 0, null: false
      t.integer :initiative_bonus,  default: 0, null: false
      t.integer :position,          null: false  # ordem no tracker (ASC)

      t.integer :hp_current, default: 0, null: false
      t.integer :hp_max,     default: 0, null: false
      t.integer :ac,         default: 10, null: false
      t.integer :temp_hp,    default: 0, null: false

      t.boolean :is_delayed,        default: false, null: false
      t.boolean :is_concentrating,  default: false, null: false
      t.string  :concentration_spell
      t.boolean :is_stabilized,     default: false, null: false
      t.boolean :is_dead,           default: false, null: false

      t.jsonb :conditions,    default: [], null: false
      t.jsonb :actions_used,  default: { action: false, bonus_action: false, movement: false, reaction: false }, null: false
      t.jsonb :death_saves,   default: { successes: 0, failures: 0 }, null: false

      t.timestamps
    end

    # Garante ordem estável dentro do mesmo combate (ASC por position).
    add_index :combat_combatants, [:combat_state_id, :position], unique: true, name: 'index_combat_combatants_on_state_and_position'
    # Lookup rápido "quais combatentes pertencem a este Character/CombatNpc".
    add_index :combat_combatants, [:combatable_type, :combatable_id], name: 'index_combat_combatants_on_combatable'
  end
end
