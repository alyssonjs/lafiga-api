class AddWallsToBattleMaps < ActiveRecord::Migration[6.0]
  # Fase D4: ferramenta wall-line. `walls` e um array de WallEdges
  # ({ x, y, side: 'top' | 'left' }) representando arestas com parede.
  #
  # Por que default `[]`: simplifica o modelo (nunca lida com nil) e mantem
  # compat com mapas antigos (a migration v1->v2 da Fase D6 ja inicializa).
  def change
    add_column :battle_maps, :walls, :jsonb, null: false, default: []
  end
end
