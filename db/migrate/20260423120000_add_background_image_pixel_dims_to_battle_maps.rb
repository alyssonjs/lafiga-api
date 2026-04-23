# frozen_string_literal: true

class AddBackgroundImagePixelDimsToBattleMaps < ActiveRecord::Migration[6.0]
  # Dimensões em pixels da imagem de fundo (apos compressao no cliente) —
  # usadas para manter a grelha (celulas) na mesma proporção ao redimensionar.
  def change
    add_column :battle_maps, :background_image_pixel_width, :integer
    add_column :battle_maps, :background_image_pixel_height, :integer
  end
end
