# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Player::SheetsController summary', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }

  let(:race) { human_race }
  let(:sub_race) { human_standard_subrace(race) }
  let(:character) { create(:character, user: user, name: 'Resumo', background: 'Teste') }
  let!(:sheet) do
    create(
      :sheet,
      character: character,
      race: race,
      sub_race: sub_race,
      current_level: 7,
      str: 16, dex: 14, con: 14, int: 8, wis: 10, cha: 10,
      hp_max: 50,
      hp_current: 50,
      metadata: {
        'current_level' => 7,
        'class_summary' => {
          'armor_proficiencies' => ['leve'],
          'weapon_proficiencies' => ['armas simples'],
          'languages' => ['Comum']
        }
      },
      race_summary: { 'name' => 'Humano', 'speed_ft' => 30 },
      class_summary: { 'name' => 'Bárbaro' }
    )
  end
  let!(:sheet_klass) { create(:sheet_klass, sheet: sheet, level: 7) }

  describe 'GET /api/v1/player/sheets/:id/summary' do
    it 'returns klasses[0].name, proficiencies structure, and equipment.inventory as array' do
      get "/api/v1/player/sheets/#{sheet.id}/summary", headers: headers

      expect(response).to have_http_status(:ok), -> { response.body }
      summary = response.parsed_body['summary']
      expect(summary).to be_a(Hash)

      klasses = summary['klasses'] || summary[:klasses]
      expect(klasses).to be_an(Array)
      expect(klasses[0]['name'] || klasses[0][:name]).to eq('Bárbaro')

      prof = summary['proficiencies'] || summary[:proficiencies]
      expect(prof).to be_a(Hash)
      expect(prof['languages'] || prof[:languages]).to be_an(Array)

      armor = prof['armor'] || prof[:armor]
      expect(armor).to be_an(Array)

      equip = summary['equipment'] || summary[:equipment]
      expect(equip).to be_a(Hash)
      inv = equip['inventory'] || equip[:inventory]
      expect(inv).to be_an(Array)
    end

    it 'includes persisted SheetItems in equipment.inventory (EquipmentProfileService path)' do
      SheetItem.create!(
        sheet: sheet,
        item_name: 'Mochila de Aventureiro',
        category: 'gear',
        quantity: 1,
        equipped: false,
        source: 'test',
        props_json: {}
      )

      get "/api/v1/player/sheets/#{sheet.id}/summary", headers: headers

      expect(response).to have_http_status(:ok), -> { response.body }
      summary = response.parsed_body['summary']
      equip = summary['equipment'] || summary[:equipment]
      inv = equip['inventory'] || equip[:inventory]
      names = inv.map { |i| i['name'] || i[:name] }
      expect(names).to include('Mochila de Aventureiro')
    end

    # Regressao: Mestre editando ficha alheia (HP, summary etc.) recebia 404
    # porque set_sheet/summary filtravam por `current_user.sheets`.
    context 'when accessed by a DM/Admin (not the sheet owner)' do
      let(:dm_role)  { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
      let(:dm_user)  { create(:user, role: dm_role) }
      let(:dm_headers) { bearer_headers_for(dm_user) }

      it 'allows DM to GET sheet summary of another player' do
        get "/api/v1/player/sheets/#{sheet.id}/summary", headers: dm_headers
        expect(response).to have_http_status(:ok), -> { response.body }
      end

      it 'allows DM to PATCH HP on another player sheet' do
        patch "/api/v1/player/sheets/#{sheet.id}",
              params: { sheet: { hp_current: 12 } }.to_json,
              headers: dm_headers.merge('Content-Type' => 'application/json')
        expect(response).to have_http_status(:ok), -> { response.body }
        expect(sheet.reload.hp_current).to eq(12)
      end

      it 'still denies access to a non-DM player accessing someone else\'s sheet' do
        other_player = create(:user, role: (Role.find_by(name: 'Player') || create(:role, name: 'Player')))
        get "/api/v1/player/sheets/#{sheet.id}/summary", headers: bearer_headers_for(other_player)
        # `summary` faz rescue StandardError => 422 (RecordNotFound do escopo
        # restrito do player). O importante e nao retornar 200 com payload.
        expect(response).not_to have_http_status(:ok)
        expect(response.parsed_body).not_to have_key('summary')
      end
    end
  end
end
