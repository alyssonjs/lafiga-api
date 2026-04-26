# frozen_string_literal: true

# CRUD de entradas do catálogo mundano (`items`) para o mestre site-wide.
# Fase 1: apenas armas (`kind: weapon`) — alinhado à aba Armas do compêndio.
class Api::V1::Admin::CatalogItemsController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :set_weapon_item, only: %i[show update destroy]

  def show
    render json: { item: serialize_item(@item) }, status: :ok
  end

  def update
    if @item.update(permitted_weapon)
      render json: { item: serialize_item(@item) }, status: :ok
    else
      render json: { errors: @item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @item.destroy!
    head :no_content
  end

  private

  def set_weapon_item
    idx = EquipmentCatalog.normalize_index(params[:api_index].to_s)
    @item = Item.weapon.find_by(api_index: idx)
    unless @item
      render json: { error: 'Not found' }, status: :not_found
      return
    end
  end

  def permitted_weapon
    p = params.require(:item).permit(:name, :category, :value_gp, :weight_kg, :description)
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
    it.as_json(only: %i[api_index name kind category value_gp weight_kg description props])
  end
end
