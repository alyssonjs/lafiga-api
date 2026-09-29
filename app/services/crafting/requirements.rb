# frozen_string_literal: true

module Crafting
  # O que uma receita pede, em unidades da BOLSA, para N unidades do produto.
  module Requirements
    module_function

    # [{ ingredient:, item_id:, need: }] — um por grupo de alternativa.
    #
    # Só ingrediente que LIGA a um item entra: magia e texto livre não estão na
    # bolsa (a mesa resolve). Num grupo "Fungo OU Ácido" vale a primeira opção
    # que `available` cobre; se nenhuma cobre, a primeira — é a que a tela vai
    # dizer que falta.
    def of(recipe, quantity, available: ->(_item_id) { 0 })
      recipe.ingredients.group_by { |i| i.alternative_group || "solo-#{i.id}" }.each_value.filter_map do |grupo|
        itens = grupo.select(&:ingredient_item_id)
        next if itens.empty?

        need = ->(ing) { (ing.quantity.to_d * quantity).ceil }
        ing = itens.find { |i| available.call(i.ingredient_item_id) >= need.call(i) } || itens.first
        { ingredient: ing, item_id: ing.ingredient_item_id, need: need.call(ing) }
      end
    end

    # Reserva o material das criações EM ANDAMENTO, na ordem em que começaram:
    # a mais antiga fica com o que há, a seguinte com o que sobra.
    #
    # Devolve `[reservado, por_criacao]`:
    #   reservado   = { item_id => total reservado }
    #   por_criacao = { craft_id => [{ ingredient:, item_id:, need:, available:, missing: }] }
    def reserve(crafts, inventory)
      reservado = Hash.new(0)
      por_criacao = {}
      crafts.select { |c| c.in_progress? && c.crafting_recipe }.sort_by { |c| [c.created_at, c.id] }.each do |c|
        livre = ->(id) { inventory.total(id) - reservado[id] }
        por_criacao[c.id] = of(c.crafting_recipe, c.quantity, available: livre).map do |r|
          sobra = livre.call(r[:item_id])
          reservado[r[:item_id]] += r[:need]
          r.merge(available: [sobra, 0].max, missing: [r[:need] - sobra, 0].max)
        end
      end
      [reservado, por_criacao]
    end
  end
end
