# frozen_string_literal: true

require 'rails_helper'

# Biblioteca de mapas por sessão: `battle_map_id` = mapa ATIVO (o que a mesa vê)
# e `schedule_battle_maps` = mapas VINCULADOS que o mestre alterna.
RSpec.describe 'Api::V1::Player::Schedules mapas', type: :request do
  let(:dm_role)     { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:dm)     { create(:user, role: dm_role) }
  let(:player) { create(:user, role: player_role) }

  let(:group)    { create(:group, dm_user: dm) }
  let(:schedule) { create(:schedule, group: group, created_by_user: dm) }
  let(:mapa_a)   { create(:battle_map, user: dm, group: group, name: 'Cidade') }
  let(:mapa_b)   { create(:battle_map, user: dm, group: group, name: 'Estalagem') }

  def attach(map, as: dm)
    post "/api/v1/player/schedules/#{schedule.id}/battle_maps",
         params: { battle_map_id: map.id }, headers: bearer_headers_for(as), as: :json
  end

  def activate(map, as: dm)
    post "/api/v1/player/schedules/#{schedule.id}/activate_battle_map",
         params: { battle_map_id: map.id }, headers: bearer_headers_for(as), as: :json
  end

  describe 'vincular' do
    it 'vincula o mapa e o primeiro vira o ATIVO' do
      attach(mapa_a)

      expect(response).to have_http_status(:ok)
      expect(schedule.reload.battle_map_id).to eq(mapa_a.id)
      expect(schedule.linked_battle_maps).to contain_exactly(mapa_a)
    end

    it 'o segundo vínculo NAO troca o mapa ativo sozinho' do
      attach(mapa_a)
      attach(mapa_b)

      expect(schedule.reload.battle_map_id).to eq(mapa_a.id)
      expect(schedule.linked_battle_maps).to contain_exactly(mapa_a, mapa_b)
    end

    it 'vincular duas vezes nao duplica' do
      attach(mapa_a)
      attach(mapa_a)

      expect(response).to have_http_status(:ok)
      expect(schedule.reload.schedule_battle_maps.count).to eq(1)
    end

    it 'lista os vinculados no payload, marcando o ativo' do
      attach(mapa_a)
      attach(mapa_b)

      maps = response.parsed_body.dig('schedule', 'battle_maps')
      expect(maps.map { |m| m['name'] }).to contain_exactly('Cidade', 'Estalagem')
      expect(maps.find { |m| m['active'] }['id']).to eq(mapa_a.id)
    end

    it '404 para mapa inexistente' do
      post "/api/v1/player/schedules/#{schedule.id}/battle_maps",
           params: { battle_map_id: 0 }, headers: bearer_headers_for(dm), as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'trocar o mapa ativo' do
    it 'troca o ativo entre os vinculados' do
      attach(mapa_a)
      attach(mapa_b)

      activate(mapa_b)

      expect(response).to have_http_status(:ok)
      expect(schedule.reload.battle_map_id).to eq(mapa_b.id)
    end

    it 'ativar um mapa nao vinculado vincula na hora (um passo so)' do
      activate(mapa_b)

      expect(response).to have_http_status(:ok)
      expect(schedule.reload.battle_map_id).to eq(mapa_b.id)
      expect(schedule.linked_battle_maps).to include(mapa_b)
    end

    it 'avisa a mesa em tempo real com o mapa novo' do
      attach(mapa_a)
      expect(Combat::Broadcaster).to receive(:session_meta_changed) do |sched|
        expect(sched.battle_map_id).to eq(mapa_b.id)
      end

      activate(mapa_b)
    end
  end

  describe 'desvincular' do
    it 'remove o vinculo' do
      attach(mapa_a)
      attach(mapa_b)

      delete "/api/v1/player/schedules/#{schedule.id}/battle_maps/#{mapa_b.id}",
             headers: bearer_headers_for(dm)

      expect(response).to have_http_status(:ok)
      expect(schedule.reload.linked_battle_maps).to contain_exactly(mapa_a)
    end

    it 'desvincular o ATIVO promove o proximo — a mesa nunca fica num mapa fora da sessao' do
      attach(mapa_a)
      attach(mapa_b)
      activate(mapa_b)

      delete "/api/v1/player/schedules/#{schedule.id}/battle_maps/#{mapa_b.id}",
             headers: bearer_headers_for(dm)

      expect(schedule.reload.battle_map_id).to eq(mapa_a.id)
    end

    it 'desvincular o ultimo deixa a sessao sem mapa ativo' do
      attach(mapa_a)

      delete "/api/v1/player/schedules/#{schedule.id}/battle_maps/#{mapa_a.id}",
             headers: bearer_headers_for(dm)

      expect(schedule.reload.battle_map_id).to be_nil
    end
  end

  describe 'autorizacao' do
    it 'jogador nao gerencia os mapas da mesa' do
      attach(mapa_a, as: player)

      expect(response).to have_http_status(:forbidden)
      expect(schedule.reload.battle_map_id).to be_nil
    end

    it 'jogador nao troca o mapa ativo' do
      attach(mapa_a)

      activate(mapa_b, as: player)

      expect(response).to have_http_status(:forbidden)
      expect(schedule.reload.battle_map_id).to eq(mapa_a.id)
    end
  end
end
