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
      color: asset.color,
      enabled: asset.enabled,
      userId: asset.user_id,
      imageUrl: image_url_for(asset),
      createdAt: asset.created_at&.iso8601,
      updatedAt: asset.updated_at&.iso8601,
    }
  end

  def self.serialize_collection(list)
    list.map { |a| serialize(a) }
  end

  # Path relativo (sem host) — não depende de default_url_options[:host],
  # que não está setado em test/jobs. Front prefixa com env.apiBaseUrl.
  def self.image_url_for(asset)
    return nil unless asset.respond_to?(:image) && asset.image.attached?

    Rails.application.routes.url_helpers.rails_blob_path(asset.image, only_path: true)
  rescue StandardError
    nil
  end
end
