# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Player::SheetItemsController equip', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:race) { human_race }
  let(:sub_race) { human_standard_subrace(race) }
  let(:character) { create(:character, user: user, name: 'Equip Spec PC') }
  let!(:sheet) { create(:sheet, character: character, race: race, sub_race: sub_race) }

  describe 'POST /api/v1/player/sheet_items/:id/equip' do
    it 'aceita slot de acessório novo (circlet)' do
      tiara = SheetItem.create!(
        sheet: sheet,
        item_name: 'Tiara da Luz',
        item_index: 'spec-tiara-circlet',
        category: 'Joias & Gemas',
        quantity: 1,
        equipped: false,
        source: 'test',
        props_json: { 'magical' => true }
      )

      post "/api/v1/player/sheet_items/#{tiara.id}/equip",
           params: { slot: 'circlet' },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:ok), -> { response.body }
      body = response.parsed_body['sheet_item'] || response.parsed_body[:sheet_item]
      expect(body['slot']).to eq('circlet')
      expect(body['equipped']).to eq(true)
    end

    it 'rejeita slot desconhecido' do
      item = SheetItem.create!(
        sheet: sheet,
        item_name: 'Item X',
        category: 'gear',
        quantity: 1,
        equipped: false,
        source: 'test',
        props_json: {}
      )

      post "/api/v1/player/sheet_items/#{item.id}/equip",
           params: { slot: 'invalid_slot_xyz' },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to be_present
    end

    it 'inclui weapon_props (com ammunition_index) no JSON para arma à distância com munição' do
      db_item = Item.create!(
        api_index: "spec-shortbow-ammo-#{SecureRandom.hex(4)}",
        name: 'Arco curto spec',
        kind: :weapon,
        category: 'simple',
        props: {
          'type' => 'ranged',
          'hands' => 2,
          'damage_die' => '1d6',
          'category' => 'simple',
          'properties' => %w[ammunition two-handed],
          'range' => '80/320',
          'ammunition_index' => 'flecha'
        }
      )

      si = SheetItem.create!(
        sheet: sheet,
        item_name: db_item.name,
        item_index: db_item.api_index,
        item_id: db_item.id,
        category: 'Armas',
        quantity: 1,
        equipped: false,
        source: 'test',
        props_json: {}
      )

      post "/api/v1/player/sheet_items/#{si.id}/equip",
           params: { slot: 'main_hand' },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:ok), -> { response.body }
      body = response.parsed_body['sheet_item']
      wp = body['weapon_props'] || body[:weapon_props]
      expect(wp).to be_a(Hash)
      expect(wp['ammunition_index'] || wp[:ammunition_index]).to eq('flecha')
      expect(wp['damage_die'] || wp[:damage_die]).to eq('1d6')
    end
  end
end
