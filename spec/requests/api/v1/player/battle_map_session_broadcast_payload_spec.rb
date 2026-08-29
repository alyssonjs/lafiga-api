# frozen_string_literal: true

require 'rails_helper'

# Bug de tempo real (29/08/2026): numa sessão, o Mestre desenha uma MEDIÇÃO
# (régua) e ela não aparece para nenhum jogador; o mesmo vale para névoa,
# desenhos e áreas.
#
# ⚠️ MESMA FAMÍLIA do bug corrigido em 28/08 (`persistence_version`), e por isso
# este spec existe: naquele dia a lição foi aplicada só à VERSÃO do evento, e o
# PAYLOAD ficou com o mesmo defeito. A regra vale para os dois:
#
#   **o broadcast tem de enviar o que QUEM GRAVOU gravou.**
#
# Numa sessão, os campos de mesa (tokens de criatura, fog, measurements,
# drawings, aoe_placements) são escritos no VÍNCULO (`ScheduleBattleMap`) pelo
# `MapSessionLayer` — o mapa não é tocado. Broadcastar `@map.measurements`
# manda uma lista VAZIA para todos os outros clientes: quem desenhou vê (a
# escrita otimista local), e mais ninguém.
RSpec.describe 'Broadcast dos campos de MESA', type: :request do
  let(:dono) { create(:user) }
  let(:group) { create(:group) }
  let(:schedule) { create(:schedule, group: group) }
  let(:map) { create(:battle_map, user: dono, group: group) }
  let!(:link) { ScheduleBattleMap.create!(schedule: schedule, battle_map: map) }

  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:mestre) { create(:user, role: dm_role) }
  let(:headers) { bearer_headers_for(mestre) }

  # Forma exigida por `BattleMap#measurements_well_formed` (id/color String,
  # totalFt Numeric, ownerUserId Integer, points >= 2 com x/y inteiros).
  let(:medicao) do
    [{
      'id' => 'm1', 'color' => '#3ddc84', 'totalFt' => 160.5, 'ownerUserId' => mestre.id,
      'points' => [{ 'x' => 1, 'y' => 1 }, { 'x' => 5, 'y' => 5 }],
    }]
  end

  # Captura os eventos publicados no stream deste mapa.
  def broadcasts_para_o_mapa
    capturados = []
    allow(ActionCable.server).to receive(:broadcast) do |stream, payload|
      # O stream é ESCOPADO PELA MESA (`map_<id>_s<schedule>`) quando há sessão —
      # capturar só `map_<id>` não veria nada e daria um falso negativo.
      capturados << [stream, payload] if stream.to_s.start_with?("map_#{map.id}")
    end
    yield
    capturados
  end

  describe 'medições' do
    it 'grava no VÍNCULO (o mapa não é tocado)' do
      patch "/api/v1/player/battle_maps/#{map.id}",
            params: { battle_map: { measurements: medicao }, schedule_id: schedule.id },
            headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(link.reload.measurements.size).to eq(1)
      expect(Array(map.reload.measurements)).to be_empty
    end

    it 'o BROADCAST leva a medição gravada — não a lista vazia do mapa' do
      # É este o bug: enviar `@map.measurements` numa sessão manda `[]` para
      # todos os outros clientes. Quem desenhou vê pelo otimismo local; mais
      # ninguém vê nada, e não há erro em tela.
      eventos = broadcasts_para_o_mapa do
        patch "/api/v1/player/battle_maps/#{map.id}",
              params: { battle_map: { measurements: medicao }, schedule_id: schedule.id },
              headers: headers, as: :json
      end

      medicoes = eventos.map { |(_s, p)| p[:payload] || p['payload'] }
                        .compact
                        .filter_map { |p| p[:measurements] || p['measurements'] }
      expect(medicoes).not_to be_empty, 'nenhum broadcast de measurements saiu'
      expect(medicoes.last.size).to eq(1),
                                    "broadcast levou #{medicoes.last.size} medição(ões) — o cliente do jogador apaga a régua"
    end
  end

  describe 'os demais campos de mesa têm o mesmo caminho' do
    it 'desenhos gravados no vínculo são broadcastados com conteúdo' do
      desenho = [{ 'id' => 'd1', 'points' => [[0, 0], [3, 3]], 'color' => '#fff' }]
      eventos = broadcasts_para_o_mapa do
        patch "/api/v1/player/battle_maps/#{map.id}",
              params: { battle_map: { drawings: desenho }, schedule_id: schedule.id },
              headers: headers, as: :json
      end
      enviados = eventos.map { |(_s, p)| p[:payload] || p['payload'] }
                        .compact
                        .filter_map { |p| p[:drawings] || p['drawings'] }
      expect(enviados.last).to be_present
      expect(enviados.last.size).to eq(1)
    end
  end

  describe 'SEM sessão (Map Builder) nada muda' do
    it 'grava e broadcasta a partir do próprio mapa' do
      eventos = broadcasts_para_o_mapa do
        patch "/api/v1/player/battle_maps/#{map.id}",
              params: { battle_map: { measurements: medicao } },
              headers: headers, as: :json
      end
      expect(response).to have_http_status(:ok), "resposta: #{response.status} #{response.body[0, 200]}"
      expect(map.reload.measurements.size).to eq(1)
      enviados = eventos.map { |(_s, p)| p[:payload] || p['payload'] }
                        .compact
                        .filter_map { |p| p[:measurements] || p['measurements'] }
      expect(enviados.last.size).to eq(1)
    end
  end
end
