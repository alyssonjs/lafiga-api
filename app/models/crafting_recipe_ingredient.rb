# frozen_string_literal: true

# Um ingrediente. O alvo é uma UNIÃO: item, magia ou texto livre — o banco
# garante que é exatamente um (constraint `chk_ingredient_exactly_one_target`).
class CraftingRecipeIngredient < ApplicationRecord
  UNITS = %w[ml g kg un].freeze

  belongs_to :crafting_recipe
  belongs_to :ingredient_item, class_name: 'Item', optional: true
  belongs_to :spell, optional: true

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit, inclusion: { in: UNITS }
  validate  :exactly_one_target

  # Espelha a constraint do banco na camada do model: o erro chega como
  # validação legível em vez de exceção do Postgres no meio de um import.
  def exactly_one_target
    alvos = [ingredient_item_id, spell_id, raw_text.presence].compact.size
    return if alvos == 1

    errors.add(:base, 'ingrediente precisa de exatamente um alvo: item, magia ou texto livre')
  end

  def target_kind
    return :item  if ingredient_item_id
    return :spell if spell_id
    :raw
  end

  def display_name
    ingredient_item&.name || spell&.name || raw_text
  end
end
