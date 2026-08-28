# frozen_string_literal: true

require 'rails_helper'

# Bug de tempo real (28/08/2026, sessao 74 em dev): o jogador via o companheiro
# PARADO na posicao antiga enquanto o Mestre o via andar.
#
# Causa: numa sessao, as CRIATURAS sao gravadas no vinculo
# (`ScheduleBattleMap`) e o mapa so e tocado quando muda CENARIO — mas o
# broadcast carimbava `version` a partir de `map.updated_at`. A versao ficava
# CONGELADA, todo movimento saia com o mesmo numero, e o gate do cliente
# (`shouldApplyTokenMoveVersion`, que exige `>` estrito) descartava tudo depois
# do PRIMEIRO movimento de cada token.
#
# Na sessao real: `map.updated_at` estava 13 DIAS atras do `link.updated_at`.
RSpec.describe MapSessionLayer, '#persistence_version' do
  include ActiveSupport::Testing::TimeHelpers

  let(:dono) { create(:user) }
  let(:group) { create(:group) }
  let(:schedule) { create(:schedule, group: group) }
  let(:map) { create(:battle_map, user: dono, group: group) }
  let!(:link) { ScheduleBattleMap.create!(schedule: schedule, battle_map: map) }

  def camada
    described_class.for(map: map.reload, schedule_id: schedule.id)
  end

  def criatura(id, x, y)
    { 'id' => id, 'name' => id, 'x' => x, 'y' => y, 'characterId' => "pc-#{id}" }
  end

  it 'AVANCA a cada movimento de criatura (o mapa nao e tocado, o vinculo e)' do
    camada.update!(tokens: [criatura('t1', 1, 1)])
    v1 = camada.persistence_version

    # O mapa fica com o `updated_at` velho de proposito — e o cenario dele que
    # o tocaria, e mover criatura nao mexe em cenario.
    map.update_columns(updated_at: 10.days.ago)

    travel_to(1.second.from_now) do
      camada.update!(tokens: [criatura('t1', 5, 5)])
      v2 = camada.persistence_version

      expect(v2).to be > v1,
                    'versao congelada: o cliente descarta o 2o movimento e o token "para" para os outros jogadores'
    end
  end

  it 'REGRESSAO: dois movimentos seguidos do MESMO token nao repetem a versao' do
    versoes = []
    3.times do |i|
      travel_to((i + 1).seconds.from_now) do
        camada.update!(tokens: [criatura('t1', i, i)])
        versoes << camada.persistence_version
      end
    end

    expect(versoes.uniq.size).to eq(3)
    expect(versoes).to eq(versoes.sort)
  end

  it 'avanca tambem quando muda o CENARIO (que grava no mapa, nao no vinculo)' do
    v0 = camada.persistence_version
    travel_to(1.second.from_now) do
      map.update!(tokens: [{ 'id' => 'rock', 'name' => 'Pedra', 'x' => 2, 'y' => 2, 'kind' => 'object' }])
      expect(camada.persistence_version).to be > v0
    end
  end

  it 'sem sessao (Map Builder), a versao e a do proprio mapa' do
    solta = described_class.for(map: map, schedule_id: nil)
    esperado = (map.updated_at.to_f * 1_000_000).round
    expect(solta.persistence_version).to eq(esperado)
  end
end
