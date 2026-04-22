class AddBackgroundImageOffsetToBattleMaps < ActiveRecord::Migration[6.0]
  # Fase E6.4: offset (em pixels da imagem original) para alinhar o grid do
  # mapa as linhas naturais da imagem importada. Float pra suportar resultados
  # do gridDetector com sub-pixel precision. Default 0 = comportamento atual
  # (imagem ancorada no canto superior esquerdo, sem crop).
  def change
    add_column :battle_maps, :background_image_offset_x, :float, default: 0.0, null: false
    add_column :battle_maps, :background_image_offset_y, :float, default: 0.0, null: false
  end
end
