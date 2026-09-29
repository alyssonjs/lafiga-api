# frozen_string_literal: true

# Oficina de teste: produto, materiais e uma receita "Poção de Cura" que pede
# 30 ml de Extrato + 2 un de (Fungo OU Ácido). Usado pelos specs de Criações.
module CraftingHelpers
  def oficina_item(api_index, name, kind: 'material', category: 'essence', props: {})
    Item.find_by(api_index: api_index) ||
      Item.create!(api_index: api_index, name: name, kind: kind, category: category, props: props)
  end

  def oficina_receita(produto:, ingredientes:, days: 2, dc: 12)
    r = CraftingRecipe.create!(result_item: produto, craft: 'alchemy', dc: dc, days: days,
                               tool_api_index: 'tool-suprimentos-de-alquimista')
    ingredientes.each_with_index do |(item, qtd, unit, grupo), pos|
      r.ingredients.create!(ingredient_item: item, quantity: qtd, unit: unit || 'un',
                            alternative_group: grupo, position: pos)
    end
    r
  end

  def na_bolsa(sheet, item, qtd, props: {}, equipped: false)
    SheetItem.create!(sheet: sheet, item_id: item.id, item_index: item.api_index, item_name: item.name,
                      category: 'Matérias-Primas', quantity: qtd, equipped: equipped, props_json: props)
  end
end

RSpec.configure { |c| c.include CraftingHelpers }
