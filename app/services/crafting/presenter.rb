# frozen_string_literal: true

module Crafting
  # A área de Criações de UMA ficha: as receitas que ela conhece, com o que há
  # nas bolsas, e as criações — em andamento primeiro.
  #
  # ⚠️ "Disponível" é o que o personagem TEM menos o que já está COMPROMETIDO
  # com criações em andamento. Os materiais só saem ao concluir; sem descontar
  # o comprometido, duas criações contariam o mesmo frasco e a segunda
  # descobriria a falta só no fim. Entre criações, a que começou primeiro fica
  # com o material (`Requirements.reserve`).
  class Presenter
    INCLUDES = [:result_item, { ingredients: %i[ingredient_item spell] }].freeze

    def self.call(sheet)
      new(sheet).call
    end

    def initialize(sheet)
      @sheet = sheet
    end

    def call
      inv = Inventory.new(@sheet)
      crafts = @sheet.sheet_crafts.includes(crafting_recipe: INCLUDES)
                     .order(Arel.sql("CASE WHEN sheet_crafts.status = 'in_progress' THEN 0 ELSE 1 END"), created_at: :desc, id: :desc)
                     .to_a
      comprometido, por_criacao = Requirements.reserve(crafts, inv)
      known = @sheet.sheet_known_recipes.includes(crafting_recipe: INCLUDES).map(&:crafting_recipe)
      ferramentas = RecipeJson.ferramentas_de(known + crafts.filter_map(&:crafting_recipe))

      {
        recipes: known.map { |r| receita(r, inv, comprometido, ferramentas) }
                      .sort_by { |r| r[:product] ? r[:product][:name].to_s.downcase : '' },
        crafts: crafts.map { |c| criacao(c, inv, por_criacao[c.id], ferramentas) },
      }
    end

    private

    def receita(recipe, inv, comprometido, ferramentas)
      disponivel = ->(item_id) { inv.total(item_id) - comprometido[item_id] }
      json = RecipeJson.base(recipe, ferramentas)
      json[:ingredients] = json[:ingredients].map do |ing|
        next ing.merge(have: nil, committed: 0, available: nil, where: []) unless ing[:item_id]

        ing.merge(have: inv.total(ing[:item_id]), committed: comprometido[ing[:item_id]],
                  available: disponivel.call(ing[:item_id]), where: inv.onde(ing[:item_id]))
      end
      reqs = Requirements.of(recipe, 1, available: disponivel)
      max = reqs.empty? ? nil : reqs.map { |r| [disponivel.call(r[:item_id]), 0].max / r[:need] }.min
      json.merge(max_craftable: max, ready: max.nil? || max >= 1)
    end

    def criacao(craft, inv, reserva, ferramentas)
      recipe = craft.crafting_recipe
      base = {
        id: craft.id,
        recipe_id: craft.crafting_recipe_id,
        product_name: craft.product_name,
        product: recipe && RecipeJson.base(recipe, ferramentas)[:product],
        tool_name: recipe && ferramentas[recipe.tool_api_index],
        dc: recipe&.dc,
        quantity: craft.quantity,
        days_required: craft.days_required.to_f,
        days_worked: craft.days_worked.to_f,
        status: craft.status,
        ready: craft.ready?,
        consumed: craft.consumed,
        product_sheet_item_id: craft.product_sheet_item_id,
        completed_at: craft.completed_at&.iso8601,
        started_at: craft.created_at&.iso8601,
        notes: craft.notes,
      }
      return base.merge(materials: [], materials_ok: true) unless reserva

      materiais = reserva.map do |r|
        { item_id: r[:item_id], name: r[:ingredient].display_name, unit: r[:ingredient].unit,
          need: r[:need], have: inv.total(r[:item_id]), available: r[:available], missing: r[:missing],
          where: inv.onde(r[:item_id]) }
      end
      base.merge(materials: materiais, materials_ok: materiais.all? { |m| m[:missing].zero? })
    end
  end
end
