# frozen_string_literal: true

# A IDENTIDADE DA GERAÇÃO do mapa da vila (09/10; a C0 de `jogo/composicao-do-mapa.md`). Ao lado da `semente`, que já
# existe, o mapa guarda QUAL gerador o fez, para a mesma semente refazer o mesmo mapa e para se saber quando um mapa
# foi feito por um gerador antigo:
#   - `versao_do_gerador`: a do código que sorteia (`VERSAO_DO_GERADOR` em `lpcMapa/lpcMundo.ts`); sobe quando a mesma
#     semente passa a dar outro mapa;
#   - `versao_dos_biomas`: a das tabelas de cada bioma (as espécies, as densidades, a paleta); sobe quando uma delas
#     muda.
# Vazias no mapa de sempre e na casca que ainda não foi gerada.
class AddGeracaoToBattleMaps < ActiveRecord::Migration[6.0]
  def change
    add_column :battle_maps, :versao_do_gerador, :integer
    add_column :battle_maps, :versao_dos_biomas, :integer
  end
end
