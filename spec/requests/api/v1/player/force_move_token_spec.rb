# frozen_string_literal: true

require 'rails_helper'

# Deslocamento FORÇADO por regra (Etapa B do `invocacoes-de-combate-plano`):
# Explosão Repulsiva, Onda Trovejante, Técnica da Mão Aberta.
#
# ⚠️ POR QUE UM ENDPOINT SEPARADO. O `move_token` normal só deixa o jogador
# mover token que ele POSSUI — e o alvo de um empurrão nunca é dele. Afrouxar
# aquela porta liberaria qualquer jogador a arrastar o token alheio a qualquer
# momento. Aqui a autorização é OUTRA e mais estreita: quem empurra é o ATOR DO
# TURNO, porque o empurrão é consequência da ação dele.
#
# ⚠️ O LIMITE DE DISTÂNCIA é a defesa contra cliente adulterado. A geometria
# completa (paredes, ocupação) segue no cliente, que tem o mapa carregado; o
# servidor garante que ninguém teleporte a criatura para o outro lado do mapa
# mandando um (x,y) qualquer.
RSpec.describe 'POST force_move_token', type: :request do
  let(:dono) { create(:user) }
  let(:group) { create(:group) }
  let(:schedule) { create(:schedule, group: group) }
  let(:map) { create(:battle_map, user: dono, group: group) }
  let!(:link) { ScheduleBattleMap.create!(schedule: schedule, battle_map: map) }

  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:mestre) { create(:user, role: dm_role) }

  # ⚠️ `let!` E personagem no grupo para AMBOS: `readable_by?` passa por
  # `Group#member?`, que é `characters.exists?(user_id:)`. Sem o personagem, o
  # jogador levaria 403 pela LEITURA — e o teste do turno passaria verde sem
  # nunca exercitar a regra de turno (falso positivo pego por reversão em 29/08).
  let(:jogador_do_turno) { create(:user) }
  let!(:pc_do_turno) { create(:character, user: jogador_do_turno, group: group) }
  let(:outro_jogador) { create(:user) }
  let!(:pc_do_outro) { create(:character, user: outro_jogador, group: group) }

  # O mapa da factory é 5×5 (coords válidas 0..4).
  # ⚠️ `npcId` é o que faz o token contar como CRIATURA (`BattleMap.creature_token?`):
  # sem ele o token é CENÁRIO e a camada o grava no MAPA, não no vínculo.
  let(:alvo) do
    { 'id' => 'tk-alvo', 'name' => 'Goblin', 'x' => 1, 'y' => 1, 'size' => 1, 'npcId' => 'npc-9' }
  end

  before { link.update!(tokens: [alvo]) }

  def empurrar(headers, x: 3, y: 1, token: 'tk-alvo')
    post "/api/v1/player/battle_maps/#{map.id}/force_move_token",
         params: { token_id: token, x: x, y: y, schedule_id: schedule.id },
         headers: headers, as: :json
  end

  def posicao
    t = Array(link.reload.tokens).find { |x| x['id'] == 'tk-alvo' }
    [t['x'], t['y']]
  end

  describe 'autorização' do
    it 'o MESTRE pode empurrar' do
      empurrar(bearer_headers_for(mestre))
      expect(response).to have_http_status(:ok)
      expect(posicao).to eq([3, 1])
    end

    context 'com combate ativo e o PC do jogador no turno' do
      before do
        cs = schedule.create_combat_state!(active: true, current_turn_index: 0, round: 1)
        cs.combat_combatants.create!(
          position: 0, combatable: pc_do_turno, name: pc_do_turno.name, initiative: 20,
        )
      end

      it 'o ATOR DO TURNO pode empurrar o token de OUTRO (é o ponto da feature)' do
        empurrar(bearer_headers_for(jogador_do_turno))
        expect(response).to have_http_status(:ok)
        expect(posicao).to eq([3, 1])
      end

      it 'um jogador FORA do turno NÃO pode' do
        # Sem esta porta, qualquer um arrasta qualquer token a qualquer hora.
        empurrar(bearer_headers_for(outro_jogador))
        expect(response).to have_http_status(:forbidden)
        expect(posicao).to eq([1, 1])
      end
    end

    it 'SEM combate ativo, jogador nenhum empurra' do
      empurrar(bearer_headers_for(jogador_do_turno))
      expect(response).to have_http_status(:forbidden)
      expect(posicao).to eq([1, 1])
    end

    it 'sem schedule_id o jogador não passa (não há turno para conferir)' do
      post "/api/v1/player/battle_maps/#{map.id}/force_move_token",
           params: { token_id: 'tk-alvo', x: 3, y: 1 },
           headers: bearer_headers_for(jogador_do_turno), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'limites' do
    it 'recusa deslocamento acima do teto (cliente adulterado)' do
      empurrar(bearer_headers_for(mestre), x: 1 + 20, y: 1)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(posicao).to eq([1, 1])
    end

    it 'recusa destino fora do tabuleiro' do
      empurrar(bearer_headers_for(mestre), x: -1, y: 1)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(posicao).to eq([1, 1])
    end

    it 'token inexistente é 404, não 500' do
      empurrar(bearer_headers_for(mestre), token: 'nao-existe')
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'persistência e broadcast' do
    it 'grava na CAMADA DA MESA (o alvo é criatura, vai para o vínculo)' do
      empurrar(bearer_headers_for(mestre))
      expect(posicao).to eq([3, 1])
      # O mapa não recebe criatura — é a mesma separação do resto da sessão.
      expect(Array(map.reload.tokens).find { |t| t['id'] == 'tk-alvo' }).to be_nil
    end

    it 'emite token_moved no canal DA MESA, com a versão de quem gravou' do
      eventos = []
      allow(ActionCable.server).to receive(:broadcast) do |stream, payload|
        eventos << payload if stream.to_s.start_with?("map_#{map.id}")
      end
      empurrar(bearer_headers_for(mestre))

      movidos = eventos.select { |e| (e[:event] || e['event']).to_s == 'token_moved' }
      expect(movidos).not_to be_empty, 'nenhum token_moved saiu — o token move só para quem empurrou'
      carga = movidos.last[:payload] || movidos.last['payload']
      expect(carga[:x] || carga['x']).to eq(3)
      # Versão da CAMADA: com o valor do mapa, o gate do cliente descartaria o
      # segundo empurrão do mesmo token (bug de 28/08).
      expect(carga[:version] || carga['version']).to be_positive
    end
  end
end
