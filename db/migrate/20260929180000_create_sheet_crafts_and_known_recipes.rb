# frozen_string_literal: true

# CRIAÇÕES do personagem — o irmão de "Aprendizado" para itens.
#
#   - `sheet_known_recipes`: as receitas que ESTE personagem conhece. O catálogo
#     de receitas é um só (o Mestre escreve), mas cada ficha só vê as que o
#     Mestre ensinou — é a fórmula aprendida, não a lista inteira do mundo.
#   - `sheet_crafts`: uma criação em andamento ou concluída. O Mestre inicia,
#     conta os dias sessão a sessão e conclui. ⚠️ Os materiais só saem da bolsa
#     ao CONCLUIR; até lá o que está "comprometido" é calculado das criações em
#     andamento, não separado. `consumed` guarda de onde cada coisa saiu.
#   - `crafting_recipes.tool_api_index`: a ferramenta exigida, pela chave do
#     catálogo de proficiências. As 101 de alquimia já existentes ganham os
#     suprimentos de alquimista.
class CreateSheetCraftsAndKnownRecipes < ActiveRecord::Migration[6.0]
  def up
    add_column :crafting_recipes, :tool_api_index, :string
    execute <<~SQL
      UPDATE crafting_recipes SET tool_api_index = 'tool-suprimentos-de-alquimista'
      WHERE craft = 'alchemy' AND tool_api_index IS NULL
    SQL

    create_table :sheet_known_recipes do |t|
      t.references :sheet, null: false, foreign_key: { on_delete: :cascade }
      t.references :crafting_recipe, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :by_user_id
      t.timestamps
    end
    add_index :sheet_known_recipes, %i[sheet_id crafting_recipe_id], unique: true, name: 'idx_known_recipes_sheet_recipe'

    create_table :sheet_crafts do |t|
      t.references :sheet, null: false, foreign_key: { on_delete: :cascade }
      # Nulo quando a receita é apagada depois: a criação concluída continua no
      # histórico da ficha, pelo nome guardado em `product_name`.
      t.references :crafting_recipe, foreign_key: { on_delete: :nullify }
      t.string :product_name, null: false
      t.integer :quantity, null: false, default: 1
      t.decimal :days_required, precision: 8, scale: 2, null: false
      t.decimal :days_worked, precision: 8, scale: 2, null: false, default: 0
      t.string :status, null: false, default: 'in_progress'
      t.jsonb :consumed, null: false, default: []
      t.bigint :product_sheet_item_id
      t.datetime :completed_at
      t.bigint :by_user_id
      t.text :notes
      t.timestamps
    end
    add_index :sheet_crafts, %i[sheet_id status]
  end

  def down
    drop_table :sheet_crafts
    drop_table :sheet_known_recipes
    remove_column :crafting_recipes, :tool_api_index
  end
end
