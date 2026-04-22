class CreateMonsters < ActiveRecord::Migration[6.0]
  def change
    create_table :monsters do |t|
      # Identidade canonica. `slug` espelha o `id` do MONSTER_DATABASE.ts
      # (ex.: 'mon-lemure'); `name` em PT-BR; `name_en` para fallback /
      # busca cruzada.
      t.string  :slug, null: false
      t.string  :name, null: false
      t.string  :name_en

      # Colunas indexaveis para filtros principais (size/type/CR/source).
      # O conteudo rico vai todo em `payload` JSONB para evitar 30+ colunas
      # e permitir evolucao do shape sem migration.
      t.string  :size
      t.string  :monster_type
      t.string  :alignment
      t.string  :cr,        null: false, default: '0'
      t.float   :cr_numeric, null: false, default: 0.0
      t.integer :xp,        null: false, default: 0
      t.integer :ac
      t.integer :hp
      t.string  :source,    null: false, default: 'srd' # 'srd' | 'homebrew'

      # Conteudo completo da entrada (espelha MonsterEntry do front):
      # speed, stats, savingThrows, skills, damage*, conditionImmunities,
      # senses, languages, traits, actions, reactions, legendaryActions,
      # lairActions, environment, etc.
      t.jsonb   :payload, null: false, default: {}

      t.timestamps
    end

    add_index :monsters, :slug, unique: true
    add_index :monsters, :name
    add_index :monsters, :monster_type
    add_index :monsters, :cr_numeric
    add_index :monsters, :source
    add_index :monsters, :payload, using: :gin
  end
end
