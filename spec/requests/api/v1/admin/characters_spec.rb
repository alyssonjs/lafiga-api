# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::CharactersController', type: :request do
  let(:admin_role) { Role.find_by(name: 'Admin') || create(:role, name: 'Admin') }
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }

  let(:admin_user)   { create(:user, role: admin_role,  name: 'Mestre') }
  let(:dm_user)      { create(:user, role: dm_role, name: 'DM Site') }
  let(:player_alice) { create(:user, role: player_role, name: 'Alice', username: 'alice') }
  let(:player_bob)   { create(:user, role: player_role, name: 'Bob',   username: 'bob') }

  let(:admin_headers)  { bearer_headers_for(admin_user) }
  let(:dm_headers)     { bearer_headers_for(dm_user) }
  let(:player_headers) { bearer_headers_for(player_alice) }

  describe 'GET /api/v1/admin/characters' do
    let(:race)     { human_race }
    let(:sub_race) { human_standard_subrace(race) }

    let!(:alice_pc) do
      create(:character, user: player_alice, name: 'Aldric', background: 'Soldado').tap do |c|
        sheet = create(
          :sheet,
          character: c,
          race: race,
          sub_race: sub_race,
          current_level: 5,
          metadata: { 'current_level' => 5 }
        )
        create(:sheet_klass, sheet: sheet, level: 5)
      end
    end

    let!(:bob_pc) do
      create(:character, user: player_bob, name: 'Brienne', background: 'Nobre').tap do |c|
        sheet = create(
          :sheet,
          character: c,
          race: race,
          sub_race: sub_race,
          current_level: 3,
          metadata: { 'current_level' => 3 }
        )
        create(:sheet_klass, sheet: sheet, level: 3)
      end
    end

    let!(:admin_npc) do
      create(:character, user: admin_user, name: 'Goblin Chefe', background: 'Inimigo')
    end

    it 'bloqueia player (403 — site-wide DM ou Admin)' do
      get '/api/v1/admin/characters', headers: player_headers
      expect(response).to have_http_status(:forbidden)
    end

    it 'permite utilizador com papel DM' do
      get '/api/v1/admin/characters', headers: dm_headers
      expect(response).to have_http_status(:ok)
    end

    it 'inclui pending_dm_level_up quando existe CharacterDmLevelUnlock' do
      CharacterDmLevelUnlock.create!(character: alice_pc, unlocked_by_user: dm_user)
      get '/api/v1/admin/characters', headers: admin_headers
      row = response.parsed_body['characters'].find { |c| c['id'] == alice_pc.id }
      expect(row['pending_dm_level_up']).to be true
      row_b = response.parsed_body['characters'].find { |c| c['id'] == bob_pc.id }
      expect(row_b['pending_dm_level_up']).to be false
    end

    it 'lista personagens de TODOS os jogadores' do
      get '/api/v1/admin/characters', headers: admin_headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      ids = json.fetch('characters').map { |c| c['id'] }
      expect(ids).to include(alice_pc.id, bob_pc.id, admin_npc.id)
      expect(json.dig('meta', 'total')).to be >= 3
    end

    it 'expoe envelope rico (sheet, main_class, sheet_id) compativel com o player endpoint' do
      get '/api/v1/admin/characters', headers: admin_headers

      row = response.parsed_body['characters'].find { |c| c['id'] == alice_pc.id }
      expect(row).to be_present
      expect(row['sheet_id']).to eq(alice_pc.sheet.id)
      expect(row.dig('main_class', 'name')).to be_a(String).and(be_present)
      expect(row.dig('sheet', 'race', 'name')).to eq('Humano')
      expect(row.dig('sheet', 'metadata', 'current_level')).to eq(5)
    end

    it 'inclui o bloco user com id, name, username, email para o DM identificar o dono' do
      get '/api/v1/admin/characters', headers: admin_headers

      row = response.parsed_body['characters'].find { |c| c['id'] == alice_pc.id }
      expect(row['user']).to include(
        'id' => player_alice.id,
        'name' => 'Alice',
        'username' => 'alice',
        'email' => player_alice.email
      )
    end

    it 'filtra por user_id' do
      get '/api/v1/admin/characters', params: { user_id: player_bob.id }, headers: admin_headers

      ids = response.parsed_body['characters'].map { |c| c['id'] }
      expect(ids).to eq([bob_pc.id])
    end

    it 'filtra por status' do
      bob_pc.update!(status: :draft)
      get '/api/v1/admin/characters', params: { status: 'draft' }, headers: admin_headers

      ids = response.parsed_body['characters'].map { |c| c['id'] }
      expect(ids).to include(bob_pc.id)
      expect(ids).not_to include(alice_pc.id)
    end

    it 'filtra por busca textual no nome (q)' do
      get '/api/v1/admin/characters', params: { q: 'aldr' }, headers: admin_headers

      names = response.parsed_body['characters'].map { |c| c['name'] }
      expect(names).to include('Aldric')
      expect(names).not_to include('Brienne')
    end

    it 'pagina respeitando page/per_page' do
      get '/api/v1/admin/characters', params: { page: 1, per_page: 1 }, headers: admin_headers

      json = response.parsed_body
      expect(json['characters'].size).to eq(1)
      expect(json.dig('meta', 'page')).to eq(1)
      expect(json.dig('meta', 'per_page')).to eq(1)
      expect(json.dig('meta', 'total')).to be >= 3
    end
  end

  describe 'GET /api/v1/admin/characters/:id' do
    let!(:alice_pc) { create(:character, user: player_alice, name: 'Solo', background: 'Eremita') }

    it 'retorna envelope rico com user para DM' do
      get "/api/v1/admin/characters/#{alice_pc.id}", headers: admin_headers
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json.dig('character', 'id')).to eq(alice_pc.id)
      expect(json.dig('character', 'user', 'id')).to eq(player_alice.id)
    end

    it 'bloqueia player com 403' do
      get "/api/v1/admin/characters/#{alice_pc.id}", headers: player_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'PATCH /api/v1/admin/characters/:id' do
    let!(:re_pc) { create(:character, user: player_alice, name: 'ReassignTarget', background: 'Eremita') }
    let!(:re_pc_sheet) { create(:sheet, character: re_pc, metadata: { 'race_choices' => {} }) }

    it 'com make_npc transfere dono para o DM autenticado e persiste metadata.general.isNPC' do
      patch "/api/v1/admin/characters/#{re_pc.id}",
            params: { character: { make_npc: true } },
            headers: dm_headers,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(re_pc.reload.user_id).to eq(dm_user.id)
      expect(re_pc_sheet.reload.metadata.dig('general', 'isNPC')).to eq(true)
      json = response.parsed_body['character']
      expect(json.dig('user', 'id')).to eq(dm_user.id)
    end

    let!(:npc_owned_by_dm) { create(:character, user: dm_user, name: 'NpcHandoff', background: 'Eremita') }
    let!(:npc_owned_by_dm_sheet) do
      create(:sheet, character: npc_owned_by_dm, metadata: { 'general' => { 'isNPC' => true } })
    end

    it 'ao atribuir dono a jogador remove metadata.general.isNPC' do
      patch "/api/v1/admin/characters/#{npc_owned_by_dm.id}",
            params: { character: { user_id: player_alice.id } },
            headers: dm_headers,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(npc_owned_by_dm.reload.user_id).to eq(player_alice.id)
      expect(npc_owned_by_dm_sheet.reload.metadata.dig('general', 'isNPC')).to eq(false)
    end

    it 'permite DM alterar user_id e devolve envelope com user atualizado' do
      patch "/api/v1/admin/characters/#{re_pc.id}",
            params: { character: { user_id: player_bob.id } },
            headers: dm_headers,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(re_pc.reload.user_id).to eq(player_bob.id)
      json = response.parsed_body['character']
      expect(json.dig('user', 'id')).to eq(player_bob.id)
      expect(json.dig('user', 'username')).to eq('bob')
    end

    it 'bloqueia player com 403' do
      patch "/api/v1/admin/characters/#{re_pc.id}",
            params: { character: { user_id: player_bob.id } },
            headers: player_headers,
            as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
