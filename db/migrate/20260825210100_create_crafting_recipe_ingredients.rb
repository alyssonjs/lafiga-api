# frozen_string_literal: true

# Um ingrediente de uma receita.
#
# ⚠️ O alvo é uma UNIÃO de três, não só o item — descoberto lendo a planilha:
#   - `ingredient_item_id`: o caso normal (matéria-prima ou item do catálogo).
#     É o LINK que permite ao NPC ferreiro exigir o material da bolsa.
#   - `spell_id`: magia como ingrediente. O manual usa "Mg X" em 23 receitas —
#     a Poção de Amizade Animal pede a própria magia na mistura.
#   - `raw_text`: o que não é nem item nem magia. A Poção de Resistência pede um
#     "Componente Extra" que ESCOLHE o tipo de dano na hora — é uma escolha, não
#     um item. Por isso `ingredient_item_id` NÃO pode ser NOT NULL.
class CreateCraftingRecipeIngredients < ActiveRecord::Migration[6.0]
  def change
    create_table :crafting_recipe_ingredients do |t|
      t.references :crafting_recipe, null: false, foreign_key: true, index: true
      t.references :ingredient_item, null: true, foreign_key: { to_table: :items }, index: true
      t.references :spell, null: true, foreign_key: true, index: true
      t.string  :raw_text

      t.decimal :quantity, precision: 10, scale: 2, null: false, default: 1
      # ml, g, un — matéria-prima se mede, não se conta.
      t.string  :unit, null: false, default: 'un'

      # "10ml Fungo OU 5ml Componente Ácido": mesmo grupo = alternativas entre si.
      # Sem isto viravam dois ingredientes obrigatórios e a receita ficava cara.
      t.integer :alternative_group

      # Ingrediente-ESCOLHA: quem fabrica decide qual material entra, e essa
      # escolha muda o resultado (o tipo de dano da Poção de Resistência).
      t.boolean :is_choice, null: false, default: false

      t.integer :position, null: false, default: 0
      t.timestamps
    end

    # Exatamente UM dos três alvos. Sem isto, um ingrediente órfão (os três nulos)
    # passaria despercebido e a receita ficaria silenciosamente incompleta.
    execute <<~SQL
      ALTER TABLE crafting_recipe_ingredients
      ADD CONSTRAINT chk_ingredient_exactly_one_target CHECK (
        (CASE WHEN ingredient_item_id IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN spell_id           IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN raw_text           IS NOT NULL THEN 1 ELSE 0 END) = 1
      )
    SQL
  end
end
