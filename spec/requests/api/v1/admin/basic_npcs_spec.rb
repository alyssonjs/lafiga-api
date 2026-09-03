# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::BasicNpcs', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:dm) { create(:user, role: dm_role) }
  let(:player) { create(:user, role: player_role) }

  let!(:guarda) do
    BasicNpc.create!(
      slug: 'guarda', name: 'Guarda', role: 'Guarda de portão',
      hp: 11, ac: 16, initiative_bonus: 1,
      speed_modes: { 'walk' => 30 },
      stats: { 'str' => 13, 'dex' => 12, 'con' => 12, 'int' => 10, 'wis' => 11, 'cha' => 10 },
      attacks: [{ 'name' => 'Lança', 'bonus' => '+3', 'damage' => '1d6+1' }]
    )
  end

  # ⚠️ NPC basico e BASTIDOR de mesa: o jogador nao escolhe um guarda de portao
  # como escolhe um familiar. Nao ha endpoint publico, e o gate e 403 (nao 401,
  # que dispararia logout global no apiClient).
  describe 'so o Mestre ve' do
    it 'jogador comum recebe 403' do
      get '/api/v1/admin/basic_npcs', headers: bearer_headers_for(player)
      expect(response).to have_http_status(:forbidden)
    end

    it 'o Mestre lista' do
      get '/api/v1/admin/basic_npcs', headers: bearer_headers_for(dm)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['basic_npcs'].first['name']).to eq('Guarda')
    end

    it 'jogador nao cria' do
      expect do
        post '/api/v1/admin/basic_npcs',
             params: { basic_npc: { name: 'Do jogador' } },
             headers: bearer_headers_for(player)
      end.not_to change(BasicNpc, :count)

      expect(response).to have_http_status(:forbidden)
    end
  end

  # ⚠️ Array de HASHES: `attacks: []` cru DESCARTA o conteudo e o NPC nasce sem
  # ataque nenhum — o mesmo defeito que o catalogo de companheiros teve.
  it 'persiste os ataques (hashes dentro de array)' do
    patch "/api/v1/admin/basic_npcs/#{guarda.slug}",
          params: { basic_npc: {
            attacks: [{ name: 'Besta leve', bonus: '+3', damage: '1d8+1' }],
          } }.to_json,
          headers: bearer_headers_for(dm).merge('CONTENT_TYPE' => 'application/json')

    expect(response).to have_http_status(:ok)
    expect(guarda.reload.attacks.first['name']).to eq('Besta leve')
    expect(guarda.attacks.first['damage']).to eq('1d8+1')
  end

  # ⚠️ Chave desconhecida viraria dado morto que o front nunca le.
  it 'higieniza stats e modos de deslocamento na escrita' do
    patch "/api/v1/admin/basic_npcs/#{guarda.slug}",
          params: { basic_npc: {
            stats: { str: 18, luck: 99 },
            speed_modes: { walk: 30, fly: 0, teleport: 60 },
          } }.to_json,
          headers: bearer_headers_for(dm).merge('CONTENT_TYPE' => 'application/json')

    guarda.reload
    expect(guarda.stats).to eq({ 'str' => 18 })
    expect(guarda.speed_modes).to eq({ 'walk' => 30 })
  end

  it 'o shape da sessao e o do formulario simples — copia direta' do
    linha = guarda.as_session_npc_json

    expect(linha[:name]).to eq('Guarda')
    expect(linha[:hp]).to eq(11)
    expect(linha[:maxHp]).to eq(11)
    expect(linha[:ac]).to eq(16)
    expect(linha[:speed]).to eq(30)
    expect(linha[:speedModes]).to eq({ 'walk' => 30 })
    expect(linha[:attacks].first['name']).to eq('Lança')
  end

  it 'token da biblioteca vira URL' do
    guarda.update!(token_map_asset_id: 77)
    expect(guarda.as_session_npc_json[:tokenImageUrl]).to eq('/api/v1/admin/map_assets/77/image?v=77')
  end
end
