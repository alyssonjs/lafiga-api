# frozen_string_literal: true

# Página pública de mapas (o "mapa-múndi" da mesa).
#
# Dois sinalizadores, e não uma tabela de configuração, porque a pergunta é
# sempre feita POR MAPA e respondida pelo dono dele:
#   - `public_listed`: o mapa aparece na lista que qualquer jogador pode abrir.
#   - `public_main`:   o mapa que abre em tela cheia na página pública. A
#     invariante de UM único principal é do controller (setar um desliga os
#     outros) — um unique index parcial recusaria a troca em vez de resolvê-la.
#
# Aditiva, default false: nenhum mapa existente fica exposto por engano.
class AddPublicMapFlagsToBattleMaps < ActiveRecord::Migration[6.0]
  def change
    add_column :battle_maps, :public_listed, :boolean, default: false, null: false
    add_column :battle_maps, :public_main, :boolean, default: false, null: false
    add_index :battle_maps, :public_listed, where: 'public_listed'
  end
end
