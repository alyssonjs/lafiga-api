# frozen_string_literal: true

# Receitas de criação — o catálogo que o MESTRE escreve: o produto, os materiais
# (itens do banco, com quantidade), os dias, a CD e a ferramenta.
#
# Grava pelo mesmo `Crafting::RecipeWriter` do editor de item do compêndio: as
# duas telas mexem na mesma receita e não podem discordar do formato.
class Api::V1::Admin::CraftingRecipesController < ApplicationController
  PER_PAGE_MAX = 100

  before_action :authorize_site_wide_dm
  before_action :set_recipe, only: %i[show update destroy]

  # GET /api/v1/admin/crafting_recipes?q=&craft=&page=&per_page=
  def index
    base = CraftingRecipe.joins(:result_item)
    base = base.where(craft: params[:craft]) if params[:craft].present?
    base = Crafting::Busca.nome(base, 'items.name', params[:q])
    page, per = paginacao
    # Ids primeiro, receitas depois: `includes` + ordem por coluna de outra
    # tabela faz o Rails trocar o preload por um JOIN gigante com LIMIT.
    ids = base.order(Crafting::Busca.ordem('items.name', params[:q])).limit(per).offset((page - 1) * per).pluck(:id)
    recipes = CraftingRecipe.where(id: ids).includes(Crafting::Presenter::INCLUDES).index_by(&:id).values_at(*ids).compact
    ferramentas = Crafting::RecipeJson.ferramentas_de(recipes)
    render json: {
      crafting_recipes: recipes.map { |r| Crafting::RecipeJson.base(r, ferramentas) },
      meta: { page: page, per_page: per, total: base.count },
    }, status: :ok
  end

  def show
    render json: { crafting_recipe: json(@recipe) }, status: :ok
  end

  # POST body: { crafting_recipe: { result_item_id, craft, tool_api_index, dc,
  #   days, craft_cost_gp, processes, notes,
  #   ingredients: [{ item_id | item_index | spell_id | raw_text, quantity, unit,
  #                   alternative_group, is_choice }] } }
  #
  # Uma receita por item (`result_item_id` é único): criar a segunda responde 422
  # com o id da que já existe, para a tela abri-la em vez de duplicar.
  def create
    c = payload
    item = Item.find_by(id: c['result_item_id'])
    return render(json: { errors: 'Escolha o item que a receita cria' }, status: :unprocessable_entity) unless item

    if (existente = CraftingRecipe.find_by(result_item_id: item.id))
      return render(json: { errors: "#{item.name} já tem receita", crafting_recipe_id: existente.id },
                    status: :unprocessable_entity)
    end

    recipe = Crafting::RecipeWriter.call(CraftingRecipe.new(result_item: item), c)
    render json: { crafting_recipe: json(recipe) }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # PATCH — o produto não muda (é a identidade da receita); o resto é regravado.
  def update
    recipe = Crafting::RecipeWriter.call(@recipe, payload.except('result_item_id'))
    render json: { crafting_recipe: json(recipe) }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # DELETE — quem a conhecia esquece; a criação CONCLUÍDA fica no histórico
  # pelo nome. ⚠️ Recusa se há criação EM ANDAMENTO: sem a receita ela não
  # teria mais como ser concluída.
  def destroy
    andamento = @recipe.sheet_crafts.in_progress.count
    if andamento.positive?
      return render(json: { errors: "#{andamento} criação(ões) em andamento usam esta receita" },
                    status: :unprocessable_entity)
    end

    @recipe.destroy!
    head :no_content
  end

  # GET /api/v1/admin/crafting_recipes/items?q=&kind=
  # Itens do banco para os seletores de PRODUTO e de MATERIAL — todos os tipos,
  # inclusive mágicos. `recipe_id` diz se o item já tem receita.
  def items
    rel = Item.all
    rel = rel.where(kind: params[:kind]) if params[:kind].present?
    rel = Crafting::Busca.nome(rel, 'items.name', params[:q])
    per = params[:per_page].present? ? params[:per_page].to_i.clamp(1, 50) : 30
    itens = rel.order(Crafting::Busca.ordem('items.name', params[:q])).limit(per).to_a
    receitas = CraftingRecipe.where(result_item_id: itens.map(&:id)).pluck(:result_item_id, :id).to_h
    render json: {
      items: itens.map do |i|
        { id: i.id, api_index: i.api_index, name: i.name, kind: i.kind, category: i.category,
          rarity: i.rarity, unit: i.props.is_a?(Hash) ? i.props['unit'] : nil,
          value_gp: i.value_gp&.to_f, recipe_id: receitas[i.id] }
      end,
      meta: { page: 1, per_page: per, total: rel.count },
    }, status: :ok
  end

  private

  def set_recipe
    @recipe = CraftingRecipe.includes(Crafting::Presenter::INCLUDES).find_by(id: params[:id])
    render(json: { error: 'Not found' }, status: :not_found) unless @recipe
  end

  def payload
    raw = params.require(:crafting_recipe)
    raw.respond_to?(:permit!) ? raw.permit!.to_h : raw.to_h.stringify_keys
  end

  def paginacao
    page = [params[:page].to_i, 1].max
    per = params[:per_page].present? ? params[:per_page].to_i.clamp(1, PER_PAGE_MAX) : 50
    [page, per]
  end

  def json(recipe)
    Crafting::RecipeJson.base(recipe, Crafting::RecipeJson.ferramentas_de([recipe]))
  end
end
