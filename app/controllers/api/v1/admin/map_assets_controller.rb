# frozen_string_literal: true

# Fase 2.6 — biblioteca de assets do Map Builder (upload do DM).
# Criar/editar/remover exige DM site-wide; leitura serve a biblioteca
# inteira (recurso compartilhado, como klasses). Espelha o padrão dos
# demais controllers admin + upload multipart do GroupsController.
class Api::V1::Admin::MapAssetsController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :set_map_asset, only: %i[update destroy]

  def index
    assets = MapAsset.all
    assets = assets.of_kind(params[:kind]) if MapAsset::KINDS.include?(params[:kind].to_s)
    assets = assets.order(created_at: :desc)
    render json: { map_assets: MapAssetSerializer.serialize_collection(assets) }, status: :ok
  end

  def create
    asset = MapAsset.new(map_asset_params.except(:image))
    asset.user_id = @current_user.id
    asset.image.attach(params.dig(:map_asset, :image)) if params.dig(:map_asset, :image).present?

    if asset.save
      render json: { map_asset: MapAssetSerializer.serialize(asset) }, status: :created
    else
      render json: { errors: asset.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    if @map_asset.update(map_asset_params.except(:image, :kind))
      render json: { map_asset: MapAssetSerializer.serialize(@map_asset) }, status: :ok
    else
      render json: { errors: @map_asset.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @map_asset.destroy!
    render json: { message: 'Asset removido' }, status: :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_map_asset
    @map_asset = MapAsset.find_by(id: params[:id])
    render json: { error: 'Asset não encontrado' }, status: :not_found unless @map_asset
  end

  def map_asset_params
    params.require(:map_asset).permit(:name, :kind, :category, :color, :enabled, :image)
  end
end
