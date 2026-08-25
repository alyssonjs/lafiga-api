# As LINHAS da grade eram desenhadas incondicionalmente (cor fixa no canvas).
# `grid_opacity` ja existe mas — apesar do nome — controla so o VEU de terreno
# sobre a arte de fundo. Este campo e a opacidade das linhas em si:
# 1.0 = visiveis (comportamento atual), 0.0 = grade invisivel.
class AddGridLinesOpacityToBattleMaps < ActiveRecord::Migration[6.0]
  def change
    add_column :battle_maps, :grid_lines_opacity, :float, default: 1.0
  end
end
