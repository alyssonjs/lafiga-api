# frozen_string_literal: true

require 'rails_helper'

# Página pública de mapas: o mestre marca quais mapas os jogadores veem e qual
# abre em tela cheia (o mapa-múndi).
RSpec.describe 'Api::V1::Player::BattleMaps página pública', type: :request do
  let(:dm_role)  { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:dm)       { create(:user, role: dm_role) }
  # Jogador SEM grupo, sem sessão, sem vínculo nenhum — o teste é justamente
  # que a página pública não depende de vínculo.
  let(:forasteiro) { create(:user) }

  let!(:mundi)    { create(:battle_map, user: dm, name: 'Mapa Múndi',   public_main: true) }
  let!(:listado)  { create(:battle_map, user: dm, name: 'Cidade Livre', public_listed: true) }
  let!(:privado)  { create(:battle_map, user: dm, name: 'Segredo do Mestre') }

  describe 'GET /battle_maps/public' do
    it 'lista só o que o mestre expôs, com o principal identificado' do
      get '/api/v1/player/battle_maps/public', headers: bearer_headers_for(forasteiro)

      expect(response).to have_http_status(:ok)
      nomes = response.parsed_body['battle_maps'].map { |m| m['name'] }
      expect(nomes).to contain_exactly('Mapa Múndi', 'Cidade Livre')
      expect(response.parsed_body['main_id']).to eq(mundi.id)
      # O principal vem PRIMEIRO — é o que a página abre sem pensar.
      expect(nomes.first).to eq('Mapa Múndi')
    end

    it 'exige autenticação' do
      get '/api/v1/player/battle_maps/public'
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'leitura do mapa listado' do
    it 'o forasteiro abre o payload cheio de um mapa listado' do
      get "/api/v1/player/battle_maps/#{listado.id}", headers: bearer_headers_for(forasteiro)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['battle_map']['publicListed']).to be(true)
    end

    it 'mapa listado com região continua SEM as notas do mestre' do
      listado.update!(regions: [{ 'id' => 'r1', 'name' => 'Praça', 'kind' => 'poi',
                                  'rects' => [{ 'col' => 0, 'row' => 0, 'w' => 2, 'h' => 2 }],
                                  'dmNotes' => 'SEGREDO PUBLICO NAO' }])
      get "/api/v1/player/battle_maps/#{listado.id}", headers: bearer_headers_for(forasteiro)
      expect(response.body).not_to include('SEGREDO PUBLICO NAO')
    end

    it 'mapa NÃO listado continua fechado para o forasteiro' do
      get "/api/v1/player/battle_maps/#{privado.id}", headers: bearer_headers_for(forasteiro)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'os sinalizadores' do
    it 'definir um novo principal DESLIGA o anterior — um gesto, não dois' do
      patch "/api/v1/player/battle_maps/#{listado.id}",
            params: { battle_map: { public_main: true } },
            headers: bearer_headers_for(dm), as: :json

      expect(response).to have_http_status(:ok)
      expect(listado.reload.public_main).to be(true)
      expect(mundi.reload.public_main).to be(false)
    end

    it 'jogador não muda sinalizador nenhum' do
      patch "/api/v1/player/battle_maps/#{listado.id}",
            params: { battle_map: { public_listed: false } },
            headers: bearer_headers_for(forasteiro), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(listado.reload.public_listed).to be(true)
    end
  end
end
