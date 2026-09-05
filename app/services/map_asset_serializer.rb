# frozen_string_literal: true

# Serializa MapAsset no shape camelCase consumido direto pelo front
# (espelha `MapAssetRecord` em mapAssetsApi.ts). `imageUrl` é o path
# relativo do blob ActiveStorage (`/rails/active_storage/...`); o front
# prefixa com a baseURL da API — mesma estratégia do GroupSerializer.
class MapAssetSerializer
  def self.serialize(asset)
    return nil unless asset

    {
      id: asset.id,
      name: asset.name,
      kind: asset.kind,
      category: asset.category,
      groupName: asset.group_name,
      variantGroup: asset.variant_group,
      variantOrder: asset.variant_order,
      color: asset.color,
      enabled: asset.enabled,
      userId: asset.user_id,
      imageUrl: image_url_for(asset),
      sourceRef: source_ref_for(asset),
      # Sombra por stamp do catálogo ('none' | {b,x,y,i} em unidades de cena);
      # nil = o item usa o padrão do estilo (o front decide qual é).
      shadow: asset.try(:meta)&.[]('shadow'),
      createdAt: asset.created_at&.iso8601,
      updatedAt: asset.updated_at&.iso8601,
    }
  end

  def self.serialize_collection(list)
    list.map { |a| serialize(a) }
  end

  # Path relativo (sem host) — front prefixa com env.apiBaseUrl. Aponta para o
  # endpoint PRÓPRIO (map_assets#image) que serve a imagem em 1 requisição com
  # CACHE IMUTÁVEL — sem o redirect 302 do ActiveStorage (2 hits no Rails, sem
  # cache), que é o gargalo ao abrir a biblioteca (46 imagens × 2 no box 1-CPU).
  # `v=` = id do blob → muda só quando a imagem muda (re-upload) → cache eterno OK.
  # Prefixos de arquivo que as rakes de importação carimbam no anexo
  # (`ink-<aid>` objetos, `inktex-<aid>` texturas, `inkpath-<aid>` caminhos).
  # É a única marca de origem que existe: o registro não guarda de onde veio.
  SOURCE_REF_PREFIXES = %w[ink- inktex- inkpath-].freeze

  # Nome do arquivo do anexo SEM extensão quando ele veio de um catálogo
  # (ex.: "inktex-594921"); nil p/ upload do utilizador. O front decide por
  # `sourceRef.startsWith('inktex-')` que a textura segue o modelo do
  # Inkarnate (80 células por repetição, seamless) — sem isso ele teria de
  # adivinhar pela categoria, que o Mestre pode renomear.
  def self.source_ref_for(asset)
    return nil unless asset.respond_to?(:image) && asset.image.attached?

    base = asset.image.blob&.filename&.base.to_s
    SOURCE_REF_PREFIXES.any? { |p| base.start_with?(p) } ? base : nil
  rescue StandardError
    nil
  end

  def self.image_url_for(asset)
    return nil unless asset.respond_to?(:image) && asset.image.attached?

    ver = asset.image.blob&.id || asset.updated_at.to_i
    "/api/v1/admin/map_assets/#{asset.id}/image?v=#{ver}"
  rescue StandardError
    nil
  end
end
