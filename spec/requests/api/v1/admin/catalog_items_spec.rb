# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::CatalogItemsController', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:dm_user) { create(:user, role: dm_role) }
  let(:player) { create(:user, role: player_role) }

  let!(:weapon) do
    Item.create!(
      api_index: "catalog-spec-weapon-#{SecureRandom.hex(4)}",
      name: 'Arma Spec',
      kind: :weapon,
      category: 'simple',
      value_gp: 15,
      weight_kg: 1.5,
      props: { 'type' => 'melee', 'damage_die' => '1d6', 'properties' => %w[light] },
    )
  end

  describe 'GET /api/v1/admin/catalog_items/:api_index' do
    it 'retorna o item para mestre' do
      get "/api/v1/admin/catalog_items/#{weapon.api_index}", headers: bearer_headers_for(dm_user)
      expect(response).to have_http_status(:ok)
      body = response.parsed_body['item']
      expect(body['api_index']).to eq(weapon.api_index)
      expect(body['name']).to eq('Arma Spec')
    end

    it '403 para jogador' do
      get "/api/v1/admin/catalog_items/#{weapon.api_index}", headers: bearer_headers_for(player)
      expect(response).to have_http_status(:forbidden)
    end

    it '404 se nao for arma ou indice invalido' do
      get '/api/v1/admin/catalog_items/nao-existe-xyz-999', headers: bearer_headers_for(dm_user)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PATCH /api/v1/admin/catalog_items/:api_index' do
    it 'atualiza nome e props' do
      patch "/api/v1/admin/catalog_items/#{weapon.api_index}",
            params: {
              item: {
                name: 'Arma Spec Renomeada',
                category: 'martial',
                value_gp: 20,
                weight_kg: 2,
                props: { 'type' => 'melee', 'damage_die' => '1d8', 'properties' => %w[finesse] },
              },
            },
            headers: bearer_headers_for(dm_user),
            as: :json

      expect(response).to have_http_status(:ok)
      weapon.reload
      expect(weapon.name).to eq('Arma Spec Renomeada')
      expect(weapon.category).to eq('martial')
      expect(weapon.props['damage_die']).to eq('1d8')
    end
  end

  describe 'DELETE /api/v1/admin/catalog_items/:api_index' do
    it 'remove o item' do
      idx = weapon.api_index
      expect do
        delete "/api/v1/admin/catalog_items/#{idx}", headers: bearer_headers_for(dm_user)
      end.to change(Item, :count).by(-1)
      expect(response).to have_http_status(:no_content)
      expect(Item.find_by(api_index: idx)).to be_nil
    end
  end
end
