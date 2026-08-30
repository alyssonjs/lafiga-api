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
    it 'cliente antigo equipando em `circlet` cai em `helmet` (fusão de 29/08)' do
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
      # A tiara divide a CABEÇA com o elmo; o slot `circlet` morreu, mas o
      # cliente da janela de deploy não pode levar 422 — canonicaliza.
      expect(body['slot']).to eq('helmet')
      expect(body['equipped']).to eq(true)
    end

    it 'equipa uma aljava e mantém apenas uma no slot quiver' do
      first = SheetItem.create!(
        sheet: sheet, item_name: 'Aljava', item_index: 'aljava', category: 'gear',
        quantity: 1, equipped: false, source: 'test', props_json: {}
      )
      second = SheetItem.create!(
        sheet: sheet, item_name: 'Aljava reserva', item_index: 'aljava-reserva', category: 'gear',
        quantity: 1, equipped: false, source: 'test', props_json: {}
      )

      post "/api/v1/player/sheet_items/#{first.id}/equip",
           params: { slot: 'quiver' }, headers: headers, as: :json
      expect(response).to have_http_status(:ok), -> { response.body }

      post "/api/v1/player/sheet_items/#{second.id}/equip",
           params: { slot: 'quiver' }, headers: headers, as: :json
      expect(response).to have_http_status(:ok), -> { response.body }

      expect(first.reload).not_to be_equipped
      expect(first.slot).to be_nil
      expect(second.reload).to be_equipped
      expect(second.slot).to eq('quiver')
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

    it 'com battle_map_id: sincroniza a arma de mão no snapshot do token (chibiEquipment) e remove no unequip' do
      db_item = Item.create!(
        api_index: "spec-sword-#{SecureRandom.hex(4)}",
        name: 'Espada spec', kind: :weapon, category: 'martial',
        props: { 'type' => 'melee', 'hands' => 1, 'damage_die' => '1d8', 'category' => 'martial' }
      )
      si = SheetItem.create!(
        sheet: sheet, item_name: db_item.name, item_index: db_item.api_index, item_id: db_item.id,
        category: 'Armas', quantity: 1, equipped: false, source: 'test', props_json: {}
      )
      map = create(:battle_map, user: user, tokens: [
        { 'id' => 'tok-1', 'characterId' => character.id.to_s, 'x' => 1, 'y' => 1, 'size' => 1, 'name' => character.name },
      ])

      post "/api/v1/player/sheet_items/#{si.id}/equip",
           params: { slot: 'main_hand', battle_map_id: map.id }, headers: headers, as: :json
      expect(response).to have_http_status(:ok), -> { response.body }

      main = Array(map.reload.tokens).find { |t| t['id'] == 'tok-1' }['chibiEquipment']&.find { |e| e['slot'] == 'main_hand' }
      expect(main).to be_present
      expect(main['name']).to eq('Espada spec')

      post "/api/v1/player/sheet_items/#{si.id}/unequip",
           params: { battle_map_id: map.id }, headers: headers, as: :json
      expect(response).to have_http_status(:ok), -> { response.body }

      after = Array(map.reload.tokens).find { |t| t['id'] == 'tok-1' }['chibiEquipment']
      expect(Array(after).find { |e| e['slot'] == 'main_hand' }).to be_nil
    end

    it 'sem battle_map_id: equip funciona normalmente (sync é no-op)' do
      item = SheetItem.create!(
        sheet: sheet, item_name: 'Anel', item_index: 'anel-spec', category: 'Joias & Gemas',
        quantity: 1, equipped: false, source: 'test', props_json: {}
      )
      post "/api/v1/player/sheet_items/#{item.id}/equip",
           params: { slot: 'ring_left' }, headers: headers, as: :json
      expect(response).to have_http_status(:ok), -> { response.body }
    end
  end

  describe 'POST /api/v1/player/sheet_items/:id/allocate_ammunition' do
    it 'allows the owner to put ammunition into an unequipped quiver' do
      quiver = SheetItem.create!(
        sheet: sheet, item_name: 'Aljava', item_index: 'aljava', category: 'gear',
        quantity: 1, equipped: false, source: 'test'
      )
      bolts = SheetItem.create!(
        sheet: sheet, item_name: 'Virote de Besta', item_index: 'virote', category: 'Armas',
        quantity: 13, equipped: false, source: 'test'
      )

      post "/api/v1/player/sheet_items/#{bolts.id}/allocate_ammunition",
           params: { quiver_id: quiver.id, quantity: 13 },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:ok), -> { response.body }
      stored = response.parsed_body.fetch('sheet_items').find { |item| item['id'] == bolts.id }
      expect(stored.dig('props', SheetItem::AMMUNITION_CONTAINER_PROP)).to eq(quiver.id)
      expect(stored['quantity']).to eq(13)
    end
  end
end
