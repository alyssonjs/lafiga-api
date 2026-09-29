# frozen_string_literal: true

# CRIAÇÕES numa ficha — o irmão de `SheetTrainingController` para itens.
#
# O MESTRE faz tudo (decisão da mesa, 29/09): ensina a receita, inicia a
# criação, conta os dias e conclui. O jogador só vê (`Player::SheetCrafting`).
#
# Toda resposta devolve o estado INTEIRO da oficina (`crafting`), como o treino
# devolve `training`: a tela troca o que tem pelo que chegou, sem remontar.
class Api::V1::Admin::SheetCraftingController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :set_sheet
  before_action :set_craft, only: %i[update_craft complete cancel]

  # POST /api/v1/admin/sheets/:id/crafting/recipes  body: { recipe_id }
  def teach
    recipe = CraftingRecipe.find_by(id: params[:recipe_id])
    return render(json: { errors: 'Receita não encontrada' }, status: :not_found) unless recipe

    @sheet.sheet_known_recipes.find_or_create_by!(crafting_recipe: recipe) { |k| k.by_user_id = @current_user&.id }
    render_estado(:created)
  rescue ActiveRecord::RecordNotUnique
    render_estado(:created)
  end

  # DELETE /api/v1/admin/sheets/:id/crafting/recipes/:recipe_id
  # Esquecer não mexe nas criações já iniciadas com ela.
  def forget
    @sheet.sheet_known_recipes.where(crafting_recipe_id: params[:recipe_id]).destroy_all
    render_estado
  end

  # POST /api/v1/admin/sheets/:id/crafting/crafts
  # body: { craft: { recipe_id, quantity, days_required?, days_worked?, notes? } }
  #
  # Nada sai da bolsa aqui — os materiais ficam só COMPROMETIDOS até concluir.
  # `days_required` ausente = os dias da receita × a quantidade.
  def start
    c = params.require(:craft).permit(:recipe_id, :quantity, :days_required, :days_worked, :notes)
    recipe = @sheet.sheet_known_recipes.includes(crafting_recipe: :result_item)
                   .find_by(crafting_recipe_id: c[:recipe_id])&.crafting_recipe
    unless recipe
      return render(json: { errors: 'O personagem não conhece esta receita' }, status: :unprocessable_entity)
    end

    qtd = c[:quantity].presence ? c[:quantity].to_i : 1
    dias = c[:days_required].presence || (recipe.days.to_d * qtd)
    craft = @sheet.sheet_crafts.create!(
      crafting_recipe: recipe, product_name: recipe.result_item&.name || 'Item',
      quantity: qtd, days_required: dias, days_worked: c[:days_worked].presence || 0,
      notes: c[:notes].presence, by_user_id: @current_user&.id,
    )
    render_estado(:created, craft_id: craft.id)
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # PATCH /api/v1/admin/sheets/:id/crafting/crafts/:craft_id
  # body: { craft: { days_worked?, days_required?, notes? } } — parcial.
  def update_craft
    return render(json: { errors: 'Criação concluída não muda' }, status: :unprocessable_entity) unless @craft.in_progress?

    attrs = params.require(:craft).permit(:days_worked, :days_required, :notes).to_h
    attrs['notes'] = attrs['notes'].presence if attrs.key?('notes')
    @craft.update!(attrs)
    render_estado
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # POST /api/v1/admin/sheets/:id/crafting/crafts/:craft_id/complete  body: { force }
  # Material faltando = 422 com `missing`; `force: true` conclui com o que houver.
  def complete
    Crafting::Complete.call(craft: @craft, force: ActiveModel::Type::Boolean.new.cast(params[:force]) || false)
    render_estado
  rescue Crafting::Complete::MissingMaterials => e
    render json: { errors: e.message, missing: e.missing }, status: :unprocessable_entity
  rescue Crafting::Complete::Invalid => e
    render json: { errors: e.message }, status: :unprocessable_entity
  end

  # DELETE /api/v1/admin/sheets/:id/crafting/crafts/:craft_id
  # Em andamento: cancela (nada foi gasto). Concluída: sai do histórico — o que
  # foi gasto e o que foi entregue ficam como estão.
  def cancel
    @craft.destroy!
    render_estado
  end

  private

  def set_sheet
    @sheet = Sheet.find(params[:id] || params[:sheet_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end

  def set_craft
    @craft = @sheet.sheet_crafts.find_by(id: params[:craft_id])
    render(json: { error: 'Not found' }, status: :not_found) unless @craft
  end

  def render_estado(status = :ok, extra = {})
    render json: { crafting: Crafting::Presenter.call(@sheet.reload) }.merge(extra), status: status
  end
end
