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

  # Aba Armaduras do compêndio: mesmo CRUD, `kind` armor|shield.
  describe 'POST /api/v1/admin/catalog_items — kind' do
    def create_item(attrs)
      post '/api/v1/admin/catalog_items',
           params: { item: attrs },
           headers: bearer_headers_for(dm_user),
           as: :json
    end

    it 'cria armadura com kind e props de CA' do
      create_item(
        api_index: 'catalog-spec-armadura',
        kind: 'armor',
        name: 'Armadura Spec',
        category: 'medium',
        props: { 'ac_base' => 14, 'dex_cap' => 2, 'stealth_dis' => true },
      )

      expect(response).to have_http_status(:created)
      item = Item.find_by(api_index: 'catalog-spec-armadura')
      expect(item.kind).to eq('armor')
      expect(item.category).to eq('medium')
      expect(item.props['ac_base']).to eq(14)
    end

    it 'cria escudo como kind proprio' do
      create_item(api_index: 'catalog-spec-escudo', kind: 'shield', name: 'Escudo Spec',
                  category: 'shield', props: { 'ac_base' => 3 })

      expect(response).to have_http_status(:created)
      expect(Item.find_by(api_index: 'catalog-spec-escudo').kind).to eq('shield')
    end

    it 'assume weapon quando o cliente nao manda kind (compat da aba Armas)' do
      create_item(api_index: 'catalog-spec-sem-kind', name: 'Sem Kind', category: 'simple', props: {})

      expect(response).to have_http_status(:created)
      expect(Item.find_by(api_index: 'catalog-spec-sem-kind').kind).to eq('weapon')
    end

    it 'cria vestuario mundano com a peca na category' do
      create_item(api_index: 'catalog-spec-manto', kind: 'gear', name: 'Manto Spec',
                  category: 'cloak', props: { 'equip_slot' => 'cloak', 'stackable' => false })

      expect(response).to have_http_status(:created)
      item = Item.find_by(api_index: 'catalog-spec-manto')
      expect(item.kind).to eq('gear')
      expect(item.category).to eq('cloak') # vira gear_category na API publica
      expect(item.props['equip_slot']).to eq('cloak')
    end

    it 'recusa kind fora do catalogo mundano' do
      create_item(api_index: 'catalog-spec-magico', kind: 'magic_item', name: 'X', category: 'x', props: {})

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Item.find_by(api_index: 'catalog-spec-magico')).to be_nil
    end
  end

  describe 'armaduras no CRUD' do
    let!(:armor) do
      Item.create!(api_index: "catalog-spec-armor-#{SecureRandom.hex(4)}", name: 'Malha Spec',
                   kind: :armor, category: 'heavy', props: { 'ac_base' => 16, 'dex_cap' => 0 })
    end

    it 'GET encontra armadura (antes so achava arma)' do
      get "/api/v1/admin/catalog_items/#{armor.api_index}", headers: bearer_headers_for(dm_user)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['item']['kind']).to eq('armor')
    end

    it 'DELETE remove armadura e escudo (lookup nao e mais so de arma)' do
      shield = Item.create!(api_index: "catalog-spec-shield-#{SecureRandom.hex(4)}", name: 'Escudo Spec',
                            kind: :shield, category: 'shield', props: { 'ac_base' => 2 })

      expect do
        delete "/api/v1/admin/catalog_items/#{armor.api_index}", headers: bearer_headers_for(dm_user)
        delete "/api/v1/admin/catalog_items/#{shield.api_index}", headers: bearer_headers_for(dm_user)
      end.to change(Item, :count).by(-2)
      expect(response).to have_http_status(:no_content)
    end

    it 'PATCH nao troca o kind da armadura' do
      patch "/api/v1/admin/catalog_items/#{armor.api_index}",
            params: { item: { kind: 'weapon', name: 'Malha Renomeada', category: 'heavy',
                              props: { 'ac_base' => 17 } } },
            headers: bearer_headers_for(dm_user),
            as: :json

      expect(response).to have_http_status(:ok)
      armor.reload
      expect(armor.kind).to eq('armor')
      expect(armor.props['ac_base']).to eq(17)
    end
  end
end
