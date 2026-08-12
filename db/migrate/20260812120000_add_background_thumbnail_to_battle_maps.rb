# frozen_string_literal: true

# Fase perf — miniatura leve do fundo do mapa.
#
# O fundo FULL migra para Active Storage (has_one_attached :background_image),
# servido por URL. Esta coluna guarda um data URI PEQUENO (webp ~400px, gerado
# client-side no upload) para a LISTA de mapas (payload :slim) renderizar a
# miniatura sem baixar o fundo full de cada mapa. Mantém a coluna text legada
# `background_image_url` intacta (fallback + backfill).
class AddBackgroundThumbnailToBattleMaps < ActiveRecord::Migration[6.0]
  def change
    add_column :battle_maps, :background_thumbnail, :text
  end
end
