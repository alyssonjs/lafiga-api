# frozen_string_literal: true

module Crafting
  # A receita como o front a lê — igual no catálogo do Mestre e na ficha.
  module RecipeJson
    module_function

    def base(recipe, ferramentas = {})
      item = recipe.result_item
      {
        id: recipe.id,
        product: item && {
          id: item.id, api_index: item.api_index, name: item.name,
          kind: item.kind, category: item.category, rarity: item.try(:rarity),
        },
        craft: recipe.craft,
        tool_api_index: recipe.tool_api_index,
        tool_name: ferramentas[recipe.tool_api_index],
        dc: recipe.dc,
        days: recipe.days&.to_f,
        craft_cost_gp: recipe.craft_cost_gp&.to_f,
        processes: Array(recipe.processes),
        notes: recipe.notes,
        ingredients: recipe.ingredients.map { |i| ingredient(i) },
      }
    end

    def ingredient(ing)
      {
        id: ing.id,
        kind: ing.target_kind.to_s,
        item_id: ing.ingredient_item_id,
        item_index: ing.ingredient_item&.api_index,
        spell_id: ing.spell_id,
        name: ing.display_name,
        quantity: ing.quantity.to_f,
        unit: ing.unit,
        # A unidade em que a BOLSA conta este item. Diferente da da receita (a
        # Água Benta pede "50 g" de um pó vendido por unidade) = o Mestre precisa
        # ver, porque a conta de "tem/precisa" deixa de fazer sentido.
        item_unit: ing.ingredient_item&.props&.dig('unit'),
        alternative_group: ing.alternative_group,
        is_choice: ing.is_choice,
      }
    end

    # { api_index => nome } das ferramentas das receitas, numa ida ao banco.
    def ferramentas_de(recipes)
      Proficiency.where(api_index: recipes.map(&:tool_api_index).compact.uniq).pluck(:api_index, :name).to_h
    end
  end
end
