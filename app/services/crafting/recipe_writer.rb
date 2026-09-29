# frozen_string_literal: true

module Crafting
  # Grava uma receita com a lista INTEIRA de ingredientes — o único escritor,
  # chamado pelo editor de item do compêndio e pela Oficina do Mestre.
  #
  # A lista é reescrita, não mesclada: um merge deixaria o ingrediente removido
  # no editor pendurado na receita.
  #
  # ⚠️ O ingrediente liga por `item_id`/`item_index`, por `spell_id` ou vira texto
  # livre — nunca é descartado em silêncio. Antes daqui o editor do compêndio
  # não devolvia a MAGIA nem o grupo de alternativa: salvar uma receita virava a
  # magia em texto e o "Fungo OU Componente Ácido" em dois obrigatórios.
  module RecipeWriter
    module_function

    def call(recipe, raw)
      c = normalizar(raw)
      CraftingRecipe.transaction do
        recipe.assign_attributes(atributos(recipe, c))
        recipe.save!
        recipe.ingredients.destroy_all
        Array(c['ingredients']).each_with_index do |ing, pos|
          recipe.ingredients.create!(ingrediente(normalizar(ing), pos))
        end
        recipe.ingredients.reset
      end
      recipe
    end

    def atributos(recipe, c)
      attrs = {
        craft: c['craft'].presence || recipe.craft.presence || 'alchemy',
        dc: c['dc'].presence&.to_i,
        days: c['days'].presence,
        craft_cost_gp: c['craft_cost_gp'].presence,
      }
      # Chave AUSENTE não mexe: o editor do compêndio não conhece a ferramenta
      # nem as notas, e salvar por ele não pode apagá-las.
      attrs[:processes] = Array(c['processes']).map(&:to_s).reject(&:blank?) if c.key?('processes')
      attrs[:tool_api_index] = c['tool_api_index'].presence if c.key?('tool_api_index')
      attrs[:notes] = c['notes'].presence if c.key?('notes')
      attrs
    end

    def ingrediente(ing, pos)
      attrs = {
        quantity: ing['quantity'].presence || 1,
        unit: ing['unit'].presence || 'un',
        alternative_group: ing['alternative_group'].presence&.to_i,
        is_choice: ActiveModel::Type::Boolean.new.cast(ing['is_choice']) || false,
        position: pos,
      }
      item = (ing['item_id'].presence && Item.find_by(id: ing['item_id'])) ||
             (ing['item_index'].presence && Item.find_by(api_index: ing['item_index']))
      spell = !item && ing['spell_id'].presence && Spell.find_by(id: ing['spell_id'])
      if item then attrs[:ingredient_item] = item
      elsif spell then attrs[:spell] = spell
      else attrs[:raw_text] = ing['raw_text'].presence || ing['name'].presence || 'Ingrediente'
      end
      attrs
    end

    def normalizar(h)
      h = h.permit!.to_h if h.respond_to?(:permit!)
      h.to_h.stringify_keys
    end
  end
end
