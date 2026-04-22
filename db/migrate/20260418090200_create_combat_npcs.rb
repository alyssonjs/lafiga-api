class CreateCombatNpcs < ActiveRecord::Migration[6.0]
  # NPCs vivos dentro de UMA sessão de combate. Vida-curta: nascem quando o
  # DM adiciona um NPC ao tracker e existem até o fim da sessão (não são
  # promovidos para um catálogo persistente). O catálogo reutilizável de NPCs
  # da campanha (`group_npcs`) entra na Fase 2 junto com o map.
  #
  # Esta tabela armazena os atributos "estáveis" do NPC (stats, AC, attacks,
  # equipment, etc). Os atributos "vivos" do combate (initiative, conditions,
  # turn order) ficam em `combat_combatants` via associação polimórfica
  # `combatable`. Isso evita misturar dados de "ficha" do NPC com dados de
  # "estado de combate" e mantém o shape simétrico ao do `Character` (PCs).
  #
  # `monster_id` (nullable) liga o NPC ao catálogo SRD do front quando o DM
  # importa um monstro. Mantemos como string porque hoje o monsterDatabase
  # mora no front; se um dia migrarmos para uma tabela `monsters`, viramos
  # foreign key.
  def change
    create_table :combat_npcs do |t|
      t.references :schedule, null: false, foreign_key: true

      t.string  :name, null: false
      t.integer :hp_current,        default: 0, null: false
      t.integer :hp_max,            default: 0, null: false
      t.integer :ac,                default: 10, null: false
      t.integer :base_ac
      t.integer :speed
      t.string  :cr
      t.integer :proficiency_bonus
      t.string  :monster_id

      # Stats e atributos compostos como JSONB para alinhar com o shape que o
      # front já consome (sessionData.ts -> SessionNPC).
      t.jsonb :stats,           default: {}, null: false  # { str, dex, con, int, wis, cha }
      t.jsonb :saving_throws,   default: {}, null: false  # { str: 5, dex: 3, ... } (apenas proficientes)
      t.jsonb :skills,          default: {}, null: false  # { perception: 4, stealth: 6 }
      t.jsonb :attacks,         default: [], null: false  # [{ name, bonus, damage }]
      t.jsonb :equipment,       default: {}, null: false  # { weapons: [], armor, shield, customWeapons }

      t.text :notes, default: '', null: false

      t.datetime :defeated_at  # marca quando foi derrotado (sem deletar — preserva log)

      t.timestamps
    end

    add_index :combat_npcs, :schedule_id, where: 'defeated_at IS NULL', name: 'index_combat_npcs_on_schedule_id_alive'
  end
end
