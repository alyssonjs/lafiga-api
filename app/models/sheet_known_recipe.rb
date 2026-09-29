# frozen_string_literal: true

# Uma receita que o personagem CONHECE. O catálogo é um só; é o Mestre quem
# ensina — a ficha só vê (e só pode criar) o que está aqui.
class SheetKnownRecipe < ApplicationRecord
  belongs_to :sheet
  belongs_to :crafting_recipe

  validates :crafting_recipe_id, uniqueness: { scope: :sheet_id }
end
