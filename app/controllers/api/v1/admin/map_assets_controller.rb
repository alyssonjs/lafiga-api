# frozen_string_literal: true

# Fase 2.6 — biblioteca de assets do Map Builder (upload do DM).
# Criar/editar/remover exige DM site-wide; leitura serve a biblioteca
# inteira (recurso compartilhado, como klasses). Espelha o padrão dos
# demais controllers admin + upload multipart do GroupsController.
class Api::V1::Admin::MapAssetsController < ApplicationController
  # `image` é público (serve o blob com cache imutável — jogadores/DM carregam as
  # imagens do mapa sem auth de DM, igual ao antigo redirect assinado).
  before_action :authorize_site_wide_dm, except: :image
  before_action :set_map_asset, only: %i[update destroy]

  def index
    # with_attached_image: eager-load do attachment+blob → sem N+1 ao serializar a
    # biblioteca inteira (46+ itens); antes eram ~2 queries por item só p/ a URL.
    assets = MapAsset.with_attached_image
    assets = assets.of_kind(params[:kind]) if MapAsset::KINDS.include?(params[:kind].to_s)
    assets = assets.where(category: params[:category]) if params[:category].present?
    assets = assets.order(created_at: :desc)
    render json: { map_assets: MapAssetSerializer.serialize_collection(assets) }, status: :ok
  end

  # Serve a imagem do asset em 1 requisição, com CACHE IMUTÁVEL (o `?v=` no URL muda
  # quando o blob muda). Elimina o redirect 302 do ActiveStorage e permite o browser/
  # Caddy cachearem — o carregamento da biblioteca deixa de martelar o Rails.
  def image
    asset = MapAsset.with_attached_image.find_by(id: params[:id])
    return head(:not_found) unless asset&.image&.attached?

    # public → o Caddy também cacheia (menos hits no Rails). immutable → o browser
    # nem revalida (o `?v=` já invalida quando a imagem muda).
    expires_in 1.year, public: true
    response.cache_control[:extras] = ['immutable']
    send_data asset.image.download,
              type: asset.image.blob.content_type || 'application/octet-stream',
              disposition: 'inline'
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
    params.require(:map_asset).permit(:name, :kind, :category, :color, :enabled, :image, :group_name, :variant_group, :variant_order)
  end
end
