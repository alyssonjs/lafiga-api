# frozen_string_literal: true

# Receita de fabricação de um item. Ver a migration para o porquê da forma.
class CraftingRecipe < ApplicationRecord
  # Ofícios. `alchemy` é o que a planilha de poções povoa; os outros já existem
  # no vocabulário porque a estrutura é a mesma e o NPC ferreiro vai usá-los.
  CRAFTS = %w[alchemy herbalism forge cooking enchanting].freeze
  # Reagentes sem custo do manual: aplicados pelo artesão, não comprados.
  PROCESSES = ['Calor', 'Luz', 'Escuro', 'Frio', 'Eletricidade', 'Água',
               'Ativador', 'Solvente', 'Neutralizante'].freeze

  belongs_to :result_item, class_name: 'Item'
  has_many :ingredients, -> { order(:position, :id) },
           class_name: 'CraftingRecipeIngredient', dependent: :destroy
  accepts_nested_attributes_for :ingredients, allow_destroy: true

  validates :craft, presence: true, inclusion: { in: CRAFTS }
  validates :dc, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :days, :craft_cost_gp, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :for_craft, ->(c) { where(craft: c) }

  # Ingredientes que o artesão precisa TER, um por grupo de alternativa. Um
  # grupo ("Fungo ou Componente Ácido") conta uma vez só — somar os dois
  # cobraria do jogador um material que a receita nem exige.
  def required_ingredients
    obrigatorios, grupos_vistos = [], Set.new
    ingredients.each do |ing|
      g = ing.alternative_group
      if g.nil?
        obrigatorios << ing
      elsif grupos_vistos.add?(g)
        obrigatorios << ing
      end
    end
    obrigatorios
  end

  # Alternativas agrupadas: { 1 => [ing_a, ing_b] }. O front oferece a escolha.
  def alternatives
    ingredients.reject { |i| i.alternative_group.nil? }.group_by(&:alternative_group)
  end
end
