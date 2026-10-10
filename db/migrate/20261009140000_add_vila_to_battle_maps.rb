# frozen_string_literal: true

# A CASCA do mapa da vila (09/10; L1.2 do roadmap, plano B3 e D5). O mapa de um setor da campanha (o assentamento,
# 200×200, primeiro) é um `BattleMap` de `map_kind 'vila'`, mas o conteúdo não mora nele: mora em `mapa_blocos`, 40×40
# células por bloco. Assim o combate, os tokens e o canal do mapa de hoje servem à vila, e nunca há a matriz `cells`
# de um mapa grande.
#
# Campos:
#   - `armazenamento`: `inteiro` (o mapa de sempre, tudo nas colunas JSON) ou `blocos` (a casca da vila);
#   - `semente`: a do gerador do mapa (L1.3);
#   - `setor_id`: o setor da campanha que o mapa desenha (o assentamento, a floresta…).
class AddVilaToBattleMaps < ActiveRecord::Migration[6.0]
  def change
    add_column :battle_maps, :armazenamento, :string, null: false, default: 'inteiro'
    add_column :battle_maps, :semente, :bigint
    add_reference :battle_maps, :setor, foreign_key: { to_table: :setores }
  end
end
