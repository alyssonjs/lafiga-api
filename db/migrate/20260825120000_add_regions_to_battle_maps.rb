# frozen_string_literal: true

# Regiões do mapa (Fase 1) — um conjunto de células com identidade: uma vila,
# uma masmorra, um ponto de interesse.
#
# A DEFINIÇÃO da região vive aqui, no mapa: é o tabuleiro, igual para todas as
# mesas que usam este mapa. O que cada grupo já descobriu sobre ela é assunto da
# camada de sessão (`schedule_battle_maps`) e não entra nesta coluna. Misturar
# os dois é repetir o bug em que a escrita ia para a camada e a leitura saía do
# mapa — o token voltava sozinho para a posição velha.
#
# A área é guardada em RETÂNGULOS (`rects: [{col,row,w,h}]`), nunca célula a
# célula: o limite de mapa é 1000×1000 e uma lista de células chegaria a
# centenas de milhares de entradas dentro de um payload que já carrega `cells`.
#
# `dmNotes` mora dentro de cada região, mas o `BattleMapSerializer` corta o
# campo SEMPRE — não há opção de incluir. O broadcast estrutural manda o mesmo
# conteúdo para a mesa inteira; sem o corte, a nota secreta do mestre vazaria.
#
# Aditiva e sem backfill: mapas existentes ficam com `[]`.
class AddRegionsToBattleMaps < ActiveRecord::Migration[6.0]
  def change
    add_column :battle_maps, :regions, :jsonb, null: false, default: []
  end
end
