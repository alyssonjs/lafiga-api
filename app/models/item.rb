class Item < ApplicationRecord
  enum kind: {
    weapon: 'weapon', armor: 'armor', shield: 'shield', ammunition: 'ammunition',
    gear: 'gear', tool: 'tool', book: 'book', consumable: 'consumable', magic_item: 'magic_item',
    # Matéria-prima: o que se CONSOME para fabricar, não o que se usa. Um kind
    # só, sub-dividido por `category` (essence/monster-part/ore/gem/herb/...),
    # porque a família de um material muda com o mundo e trocar de kind exigiria
    # migration; trocar de category é um UPDATE.
    material: 'material',
    # Tesouro: valor guardado em forma de objeto. NÃO é matéria-prima — não se
    # consome para fabricar nada; carrega-se, vende-se e distribui-se como
    # saque. A `category` diz o tipo (`art` hoje; moeda/joia se vierem).
    treasure: 'treasure'
  }

  # A receita MORRE com o produto: ela só existe para fabricá-lo.
  has_one :crafting_recipe, foreign_key: :result_item_id, dependent: :destroy, inverse_of: :result_item
  # Já o material usado em receitas NÃO pode sumir por baixo delas — apagá-lo
  # deixaria a receita silenciosamente incompleta. `restrict_with_error` dá uma
  # mensagem em vez da exceção crua do Postgres.
  has_many :crafting_uses, class_name: 'CraftingRecipeIngredient',
           foreign_key: :ingredient_item_id, dependent: :restrict_with_error, inverse_of: :ingredient_item

  validates :api_index, presence: true, uniqueness: true
  validates :name, presence: true
  validates :kind, presence: true
end


