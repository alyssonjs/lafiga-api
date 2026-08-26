# frozen_string_literal: true

# Receita de fabricação: o que é preciso para PRODUZIR um item.
#
# Nasce da alquimia (planilha de poções + Manual do Alquimista), mas o `craft`
# já é aberto porque a mesma estrutura serve forja, herbalismo, culinária e
# encantamento — e é o que o NPC ferreiro vai consultar amanhã.
class CreateCraftingRecipes < ActiveRecord::Migration[6.0]
  def change
    create_table :crafting_recipes do |t|
      # O item PRODUZIDO. Uma receita por item, por ora — daí o índice único.
      # Quando existirem caminhos alternativos para o mesmo produto, cai o
      # unique e entra um `variant`.
      t.references :result_item, null: false, foreign_key: { to_table: :items }, index: { unique: true }

      # Ofício exigido. Não é a família do INGREDIENTE (isso é a category do
      # material): o mesmo minério vira liga na forja e reagente no encantamento.
      t.string :craft, null: false, default: 'alchemy'

      t.integer :dc
      t.decimal :days, precision: 8, scale: 2
      t.decimal :craft_cost_gp, precision: 12, scale: 2

      # Reagentes SEM custo do manual (calor, luz, escuro, frio, eletricidade,
      # água): o alquimista os APLICA, não os compra. Por isso ficam aqui como
      # processo e não como ingrediente com preço.
      t.string :processes, array: true, default: []

      # Progressão por Nível do manual: custo x1/x3/x7/x15/x30 e CD +0/+2/+4/+6/+10.
      t.jsonb :scaling, default: {}

      t.string :source
      t.text :notes
      t.timestamps
    end

    add_index :crafting_recipes, :craft
  end
end
