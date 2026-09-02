# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Catálogo de companheiros', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:dm_user) { create(:user, role: dm_role) }
  let(:player) { create(:user, role: player_role) }

  let!(:cavalo) do
    CompanionTemplate.create!(
      slug: 'cavalo-teste', name: 'Cavalo de Teste', companion_type: 'mount',
      origin: 'purchased', creature_type: 'Fera', size: 'Large',
      ac: 10, hp_max: 13, speed: '18 m', carry_capacity: 480,
      stats: { 'str' => 16, 'dex' => 10, 'con' => 12, 'int' => 2, 'wis' => 11, 'cha' => 7 },
      attacks: [{ 'name' => 'Cascos', 'damage' => '2d4+3' }],
      flags: { 'shares_senses' => false }
    )
  end

  let!(:coruja) do
    CompanionTemplate.create!(
      slug: 'coruja-teste', name: 'Coruja de Teste', companion_type: 'familiar',
      origin: 'spell', origin_spell_id: 'sp-find-familiar', size: 'Tiny',
      flags: { 'shares_senses' => true, 'deliver_touch_spells' => true }
    )
  end

  describe 'quem pode CRIAR' do
    it 'o mestre cria' do
      post '/api/v1/admin/companion_templates',
           params: { companion_template: { name: 'Grifo do DM', companion_type: 'greater_mount' } },
           headers: bearer_headers_for(dm_user)

      expect(response).to have_http_status(:created)
      expect(CompanionTemplate.find_by(slug: 'grifo-do-dm')).to be_present
    end

    # 403, nao 401: 401 dispara logout global no apiClient.
    it 'o jogador comum recebe 403 e nada e criado' do
      expect do
        post '/api/v1/admin/companion_templates',
             params: { companion_template: { name: 'Dragao do jogador', companion_type: 'mount' } },
             headers: bearer_headers_for(player)
      end.not_to change(CompanionTemplate, :count)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'leitura publica' do
    it 'lista no shape que o front consome (camelCase, bandeiras achatadas)' do
      get '/api/v1/public/companion_templates'

      expect(response).to have_http_status(:ok)
      corpo = response.parsed_body['companion_templates']
      linha = corpo.find { |t| t['templateId'] == 'coruja-teste' }

      expect(linha['type']).to eq('familiar')
      expect(linha['sharesSenses']).to be(true)
      expect(linha['deliverTouchSpells']).to be(true)
      expect(linha['originSpellId']).to eq('sp-find-familiar')
    end

    it 'filtra por tipo' do
      get '/api/v1/public/companion_templates', params: { type: 'mount' }

      ids = response.parsed_body['companion_templates'].map { |t| t['templateId'] }
      expect(ids).to include('cavalo-teste')
      expect(ids).not_to include('coruja-teste')
    end
  end

  # ⚠️ Array de HASHES em strong params: `attacks: []` cru descartaria o
  # conteudo silenciosamente e o companheiro nasceria sem ataque nenhum.
  it 'persiste ataques e acoes especiais (hashes dentro de array)' do
    patch "/api/v1/admin/companion_templates/#{cavalo.slug}",
          params: { companion_template: {
            attacks: [{ name: 'Coice', damage: '2d6+4', damageType: 'contundente' }],
            special_actions: [{ name: 'Desviar', actionCost: 'action', description: 'Vantagem em CA.' }],
          } },
          headers: bearer_headers_for(dm_user)

    expect(response).to have_http_status(:ok)
    cavalo.reload
    expect(cavalo.attacks.first['name']).to eq('Coice')
    expect(cavalo.attacks.first['damageType']).to eq('contundente')
    expect(cavalo.special_actions.first['actionCost']).to eq('action')
  end

  it 'recusa um tipo que o front nao sabe desenhar' do
    post '/api/v1/admin/companion_templates',
         params: { companion_template: { name: 'Coisa', companion_type: 'kraken' } },
         headers: bearer_headers_for(dm_user)

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
