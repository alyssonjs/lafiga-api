# frozen_string_literal: true

# CRUD de entradas do catálogo mundano (`items`) para o mestre site-wide.
# Cobre as abas Armas e Armaduras do compêndio: `kind` weapon | armor | shield
# (escudo é `kind` próprio no Item, não uma categoria de armadura).
class Api::V1::Admin::CatalogItemsController < ApplicationController
  # Kinds que este CRUD gerencia. Fora desta lista o item não é editável aqui
  # (itens mágicos têm controller próprio). `gear` cobre tanto o vestuário
  # mundano (peça em `category`) quanto o equipamento de aventura.
  # `book` entrou com a aba Livros e Tomos: os 11 livros do catalogo existiam e
  # NENHUM balde os servia, entao tambem nao dava para editar nem apagar.
  CATALOG_KINDS = %w[weapon armor shield gear tool consumable ammunition book material treasure].freeze

  before_action :authorize_site_wide_dm
  before_action :set_catalog_item, only: %i[show update destroy]

  def show
    render json: { item: serialize_item(@item) }, status: :ok
  end

  def create
    attrs = permitted_item
    # Compat: cliente antigo (aba Armas) não manda `kind`.
    kind = attrs.delete(:kind).presence || 'weapon'
    unless CATALOG_KINDS.include?(kind)
      render json: { errors: ["kind inválido: #{kind}"] }, status: :unprocessable_entity
      return
    end

    idx = EquipmentCatalog.normalize_index(attrs.delete(:api_index).to_s)
    if idx.blank?
      render json: { errors: ['API index não pode ficar em branco'] }, status: :unprocessable_entity
      return
    end

    item = Item.new(attrs.merge(api_index: idx, kind: kind))
    if item.save
      aplicar_receita!(item)
      render json: { item: serialize_item(item) }, status: :created
    else
      render json: { errors: item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    # `kind` é imutável: armadura não vira arma numa edição.
    if @item.update(permitted_item.except(:kind))
      aplicar_receita!(@item)
      render json: { item: serialize_item(@item) }, status: :ok
    else
      render json: { errors: @item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    # `destroy` (sem bang): material usado numa receita é RECUSADO pelo model
    # (`restrict_with_error`) — a mensagem chega como 422 legível em vez de um
    # 500 genérico. Apagar por baixo da receita a deixaria muda.
    if @item.destroy
      head :no_content
    else
      render json: { errors: @item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def set_catalog_item
    idx = EquipmentCatalog.normalize_index(params[:api_index].to_s)
    @item = Item.where(kind: CATALOG_KINDS).find_by(api_index: idx)
    unless @item
      render json: { error: 'Not found' }, status: :not_found
      return
    end
  end

  # A receita chega JUNTO do item (uma gravação só): salvar item e receita em
  # dois pedidos deixaria a janela em que o consumível existe sem como fabricá-lo.
  # `crafting: null` APAGA a receita; ausente não mexe nela.
  def aplicar_receita!(item)
    return unless params[:item].key?(:crafting)

    raw = params[:item][:crafting]
    if raw.blank?
      item.crafting_recipe&.destroy
      return
    end

    Crafting::RecipeWriter.call(CraftingRecipe.find_or_initialize_by(result_item_id: item.id), raw)
  end

  def permitted_item
    # `rarity` entrou com a matéria-prima (ervas têm raridade de colheita).
    p = params.require(:item).permit(:api_index, :kind, :name, :category, :value_gp, :weight_kg, :description, :rarity)
    if params[:item].key?(:props)
      raw = params[:item][:props]
      p[:props] =
        if raw.is_a?(ActionController::Parameters)
          raw.permit!.to_h
        elsif raw.is_a?(Hash)
          raw.stringify_keys
        else
          {}
        end
    end
    p
  end

  def serialize_item(it)
    json = it.as_json(only: %i[api_index name kind category value_gp weight_kg description rarity props])
    r = it.try(:crafting_recipe)
    json['crafting'] = r && {
      'craft' => r.craft, 'dc' => r.dc, 'days' => r.days&.to_f,
      'craft_cost_gp' => r.craft_cost_gp&.to_f, 'processes' => Array(r.processes),
      'tool_api_index' => r.tool_api_index,
      'ingredients' => r.ingredients.map { |i|
        { 'item_index' => i.ingredient_item&.api_index, 'spell_id' => i.spell_id, 'raw_text' => i.raw_text,
          'name' => i.display_name, 'quantity' => i.quantity.to_f, 'unit' => i.unit,
          'alternative_group' => i.alternative_group, 'is_choice' => i.is_choice }
      },
    }
    json
  end
end
