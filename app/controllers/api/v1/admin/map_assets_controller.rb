# frozen_string_literal: true

# Fase 2.6 — biblioteca de assets do Map Builder (upload do DM).
# Criar/editar/remover exige DM site-wide; leitura serve a biblioteca
# inteira (recurso compartilhado, como klasses). Espelha o padrão dos
# demais controllers admin + upload multipart do GroupsController.
class Api::V1::Admin::MapAssetsController < ApplicationController
  # `image` é público (serve o blob com cache imutável — jogadores/DM carregam as
  # imagens do mapa sem auth de DM, igual ao antigo redirect assinado).
  before_action :authorize_site_wide_dm, except: %i[image thumb]
  before_action :set_map_asset, only: %i[update destroy]

  # A biblioteca pede o CATÁLOGO INTEIRO de uma vez (a busca do painel varre
  # todas as categorias no cliente). São 16.595 objetos e 6,84 MB de JSON —
  # medido em prod: 4,0 s a carregar, 3,6 s a serializar, 3,1 s no to_json, com
  # o browser a esperar ~17 s. Recalcular isso a cada abertura é o desperdício:
  # o catálogo só muda quando alguém importa ou edita um item.
  #
  # Duas camadas, ambas invalidadas pela VERSÃO do catálogo:
  #  - Redis guarda o corpo JÁ SERIALIZADO (não o ActiveRecord) → as três fases
  #    caras desaparecem e sobra um GET no Redis;
  #  - ETag → o browser que já tem a lista recebe 304 e nem baixa os 6,84 MB.
  def index
    versao = versao_do_catalogo
    # `stale?` responde 304 sozinho quando o browser já tem esta versão.
    return unless stale?(etag: [versao, params[:kind], params[:category]], public: false)

    corpo = Rails.cache.fetch("map_assets/#{versao}/#{params[:kind]}/#{params[:category]}",
                              expires_in: 12.hours) do
      # with_attached_image: eager-load do attachment+blob → sem N+1 ao serializar
      # a biblioteca inteira; antes eram ~2 queries por item só p/ a URL.
      # ⚠️ o thumb entra no eager-load JUNTO: serializar `thumbUrl` sem ele
      # devolveria o N+1 que o `with_attached_image` tinha matado.
      assets = MapAsset.with_attached_image.with_attached_thumb
      assets = assets.of_kind(params[:kind]) if MapAsset::KINDS.include?(params[:kind].to_s)
      assets = assets.where(category: params[:category]) if params[:category].present?
      assets = assets.order(created_at: :desc)
      { map_assets: MapAssetSerializer.serialize_collection(assets) }.to_json
    end

    # `body:` e não `json:` — o corpo JÁ é JSON; `render json:` numa String
    # devolveria a string ASPADA (o payload inteiro como um literal).
    render body: corpo, content_type: 'application/json', status: :ok
  end

  # Serve a imagem do asset em 1 requisição, com CACHE IMUTÁVEL (o `?v=` no URL muda
  # quando o blob muda). Elimina o redirect 302 do ActiveStorage e permite o browser/
  # Caddy cachearem — o carregamento da biblioteca deixa de martelar o Rails.
  def image
    asset = MapAsset.with_attached_image.find_by(id: params[:id])
    return head(:not_found) unless asset&.image&.attached?

    # Registro do anexo existe, mas o arquivo pode não estar no storage (banco
    # restaurado sem `storage/`, volume perdido). Isso é "não encontrado", não
    # erro de servidor: um 500 aqui vira objeto de cenário invisível no mapa,
    # sem pista nenhuma para quem está jogando.
    data = begin
      asset.image.download
    rescue ActiveStorage::FileNotFoundError
      Rails.logger.warn(
        "[map_assets#image] blob sem arquivo no storage " \
        "asset=#{asset.id} blob=#{asset.image.blob.id} key=#{asset.image.blob.key}",
      )
      nil
    end
    return head(:not_found) if data.nil?

    # public → o Caddy também cacheia (menos hits no Rails). immutable → o browser
    # nem revalida (o `?v=` já invalida quando a imagem muda).
    expires_in 1.year, public: true
    response.cache_control[:extras] = ['immutable']
    send_data data,
              type: asset.image.blob.content_type || 'application/octet-stream',
              disposition: 'inline'
  end

  # MINIATURA da biblioteca (~160 px), mesmo contrato de cache do #image.
  # ⚠️ 404 quando não existe — o front cai na imagem cheia sozinho. Nunca
  # servir a arte grande aqui como recuo: o ponto todo é não baixar 254 KB
  # para um quadrado de 100 px, e um recuo silencioso esconderia a falha.
  def thumb
    asset = MapAsset.with_attached_thumb.find_by(id: params[:id])
    return head(:not_found) unless asset&.thumb&.attached?

    data = begin
      asset.thumb.download
    rescue ActiveStorage::FileNotFoundError
      Rails.logger.warn("[map_assets#thumb] blob sem arquivo asset=#{asset.id}")
      nil
    end
    return head(:not_found) if data.nil?

    expires_in 1.year, public: true
    response.cache_control[:extras] = ['immutable']
    send_data data,
              type: asset.thumb.blob.content_type || 'image/webp',
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

  # Impressão digital barata do catálogo. `updated_at` do registo não muda quando
  # só o ANEXO troca (foi o caso das 17.317 miniaturas), então o maior id de
  # anexo entra também — senão a lista ficaria presa numa versão velha.
  def versao_do_catalogo
    [
      MapAsset.maximum(:updated_at)&.to_i,
      MapAsset.count,
      ActiveStorage::Attachment.where(record_type: 'MapAsset').maximum(:id),
    ].join('-')
  end

  def set_map_asset
    @map_asset = MapAsset.find_by(id: params[:id])
    render json: { error: 'Asset não encontrado' }, status: :not_found unless @map_asset
  end

  def map_asset_params
    params.require(:map_asset).permit(:name, :kind, :category, :color, :enabled, :image, :group_name, :variant_group, :variant_order)
  end
end
