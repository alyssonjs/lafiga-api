# frozen_string_literal: true

# Tamanho do TOKEN do NPC (células por lado: 1 Médio, 2 Grande, 3 Enorme,
# 4 Colossal — o `TokenSize` do mapa).
#
# O Mestre redimensiona o token no mapa e o tamanho volta para o NPC do
# CATÁLOGO; da próxima vez que ele puxar esse NPC, o token já nasce do tamanho
# certo. O que estes testes guardam é o caminho de volta: sem o `basic_npc_id`
# na cópia da sessão, o front não sabe de qual NPC básico ela saiu — e o
# tamanho escolhido morreria com o token.
require 'rails_helper'

RSpec.describe 'tamanho do token do NPC', type: :request do
  let(:dm_role) { Role.find_or_create_by!(name: 'DM') }
  let(:dm) { create(:user, role: dm_role) }
  let(:headers) { bearer_headers_for(dm) }
  let(:schedule) { create(:schedule) }

  let!(:cavalaria) do
    BasicNpc.create!(slug: 'cavalaria-anao', name: 'Cavalaria Anão', hp: 15, ac: 15)
  end

  describe 'NPC básico (catálogo)' do
    it 'nasce Médio (1) e a listagem traz o tamanho' do
      get '/api/v1/admin/basic_npcs', headers: headers

      linha = response.parsed_body['basic_npcs'].find { |n| n['slug'] == 'cavalaria-anao' }
      expect(linha['token_size']).to eq(1)
    end

    it 'grava o tamanho pelo ID numérico — é o que a sessão guarda' do
      put "/api/v1/admin/basic_npcs/#{cavalaria.id}",
          params: { basic_npc: { token_size: 2 } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['basic_npc']['token_size']).to eq(2)
      expect(cavalaria.reload.token_size).to eq(2)
    end

    it 'fora de 1..4 é recusado (o mapa não desenha outro tamanho)' do
      [0, 5].each do |invalido|
        put "/api/v1/admin/basic_npcs/#{cavalaria.id}",
            params: { basic_npc: { token_size: invalido } }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
      expect(cavalaria.reload.token_size).to eq(1)
    end

    it 'o shape da sessão também carrega o tamanho' do
      cavalaria.update!(token_size: 3)
      expect(cavalaria.as_session_npc_json[:tokenSize]).to eq(3)
    end
  end

  describe 'NPC de combate (cópia na sessão)' do
    let(:base) { { name: 'Cavalaria Anão', hp_current: 15, hp_max: 15, ac: 15 } }

    it '⚠️ guarda o tamanho E o NPC básico de origem — a volta para o catálogo' do
      post "/api/v1/player/schedules/#{schedule.id}/combat_npcs",
           params: { npc: base.merge(token_size: 2, basic_npc_id: cavalaria.id) },
           headers: headers, as: :json

      expect(response).to have_http_status(:created)
      json = response.parsed_body['npc']
      expect(json['token_size']).to eq(2)
      expect(json['basic_npc_id']).to eq(cavalaria.id)

      get "/api/v1/player/schedules/#{schedule.id}/combat_npcs", headers: headers
      hidratado = response.parsed_body['npcs'].find { |n| n['id'] == json['id'] }
      expect(hidratado['token_size']).to eq(2)
      expect(hidratado['basic_npc_id']).to eq(cavalaria.id)
    end

    it 'redimensionar depois atualiza a cópia da sessão' do
      npc = create(:combat_npc, schedule: schedule, basic_npc_id: cavalaria.id)

      patch "/api/v1/player/schedules/#{schedule.id}/combat_npcs/#{npc.id}",
            params: { npc: { token_size: 3 } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(npc.reload.token_size).to eq(3)
    end

    it 'sem tamanho fica nulo (o front trata como 1) e tamanho inválido é recusado' do
      post "/api/v1/player/schedules/#{schedule.id}/combat_npcs",
           params: { npc: base }, headers: headers, as: :json
      expect(response.parsed_body['npc']['token_size']).to be_nil

      post "/api/v1/player/schedules/#{schedule.id}/combat_npcs",
           params: { npc: base.merge(token_size: 9) }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
