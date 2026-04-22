# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Player::SheetRuntimeStatesController', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:character) { create(:character, user: user) }
  let!(:sheet) { create(:sheet, character: character) }

  describe 'GET /api/v1/player/sheets/:id/runtime' do
    it 'cria runtime_state na primeira leitura e devolve defaults seguros' do
      get "/api/v1/player/sheets/#{sheet.id}/runtime", headers: headers
      expect(response).to have_http_status(:ok)
      payload = response.parsed_body['runtime_state']
      expect(payload['death_saves']).to eq('successes' => 0, 'failures' => 0, 'stable' => false)
      expect(payload['hit_dice_used']).to eq({})
      expect(payload['exhaustion']).to eq(0)
      expect(payload['conditions']).to eq([])
    end

    it 'devolve 404 se a sheet não pertence ao user' do
      other_user = create(:user)
      other_char = create(:character, user: other_user)
      other_sheet = create(:sheet, character: other_char)
      get "/api/v1/player/sheets/#{other_sheet.id}/runtime", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PATCH /api/v1/player/sheets/:id/runtime' do
    it 'aceita patch parcial em death_saves' do
      patch "/api/v1/player/sheets/#{sheet.id}/runtime",
            params: { runtime_state: { death_saves: { successes: 1, failures: 2, stable: false } } },
            headers: headers, as: :json
      expect(response).to have_http_status(:ok), -> { response.body }
      payload = response.parsed_body['runtime_state']
      expect(payload['death_saves']['successes']).to eq(1)
      expect(payload['death_saves']['failures']).to eq(2)
    end

    it 'aceita patch parcial em hit_dice_used (faz merge)' do
      sheet.runtime!.update!(hit_dice_used: { 'd10' => 1 })
      patch "/api/v1/player/sheets/#{sheet.id}/runtime",
            params: { runtime_state: { hit_dice_used: { 'd8' => 2 } } },
            headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      payload = response.parsed_body['runtime_state']
      expect(payload['hit_dice_used']).to eq('d10' => 1, 'd8' => 2)
    end

    it 'aceita patch em exhaustion' do
      patch "/api/v1/player/sheets/#{sheet.id}/runtime",
            params: { runtime_state: { exhaustion: 3 } },
            headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['runtime_state']['exhaustion']).to eq(3)
    end

    it 'rejeita exhaustion fora de 0..6 com 422' do
      patch "/api/v1/player/sheets/#{sheet.id}/runtime",
            params: { runtime_state: { exhaustion: 9 } },
            headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'aceita patch parcial em spell_slots_used (faz merge)' do
      sheet.runtime!.update!(spell_slots_used: { '1' => 2 })
      patch "/api/v1/player/sheets/#{sheet.id}/runtime",
            params: { runtime_state: { spell_slots_used: { '2' => 1, 'pact' => 1 } } },
            headers: headers, as: :json
      expect(response).to have_http_status(:ok), -> { response.body }
      payload = response.parsed_body['runtime_state']
      expect(payload['spell_slots_used']).to eq('1' => 2, '2' => 1, 'pact' => 1)
    end

    it 'aceita patch parcial em class_resources_used (Fase C - faz merge)' do
      sheet.runtime!.update!(class_resources_used: { 'rage' => 1 })
      patch "/api/v1/player/sheets/#{sheet.id}/runtime",
            params: { runtime_state: { class_resources_used: { 'ki' => 2 } } },
            headers: headers, as: :json
      expect(response).to have_http_status(:ok), -> { response.body }
      payload = response.parsed_body['runtime_state']
      expect(payload['class_resources_used']).to eq('rage' => 1, 'ki' => 2)
    end
  end

  describe 'POST /api/v1/player/sheets/:id/runtime/short_rest' do
    it 'zera death_saves e marca timestamp' do
      sheet.runtime!.update!(death_saves: { 'successes' => 2, 'failures' => 1, 'stable' => false })
      post "/api/v1/player/sheets/#{sheet.id}/runtime/short_rest", headers: headers
      expect(response).to have_http_status(:ok)
      payload = response.parsed_body['runtime_state']
      expect(payload['death_saves']).to eq('successes' => 0, 'failures' => 0, 'stable' => false)
      expect(payload['last_short_rest_at']).to be_present
    end

    it 'mantém hit_dice_used (descanso curto não recupera)' do
      sheet.runtime!.update!(hit_dice_used: { 'd10' => 2 })
      post "/api/v1/player/sheets/#{sheet.id}/runtime/short_rest", headers: headers
      expect(response.parsed_body['runtime_state']['hit_dice_used']).to eq('d10' => 2)
    end

    it 'reseta apenas pact slots em spell_slots_used (Bruxo)' do
      sheet.runtime!.update!(spell_slots_used: { '1' => 1, 'pact' => 1 })
      post "/api/v1/player/sheets/#{sheet.id}/runtime/short_rest", headers: headers
      expect(response.parsed_body['runtime_state']['spell_slots_used']).to eq('1' => 1)
    end
  end

  describe 'POST /api/v1/player/sheets/:id/runtime/long_rest' do
    let!(:sheet_klass) { create(:sheet_klass, sheet: sheet, level: 6) }

    it 'zera death_saves, reduz exhaustion e recupera hit dice' do
      sheet.runtime!.update!(
        death_saves: { 'successes' => 2, 'failures' => 1, 'stable' => false },
        exhaustion:  3,
        hit_dice_used: { 'd10' => 4 }
      )
      post "/api/v1/player/sheets/#{sheet.id}/runtime/long_rest", headers: headers
      expect(response).to have_http_status(:ok)
      payload = response.parsed_body['runtime_state']
      expect(payload['death_saves']).to eq('successes' => 0, 'failures' => 0, 'stable' => false)
      expect(payload['exhaustion']).to eq(2)
      expect(payload['hit_dice_used']).to eq('d10' => 1)
      expect(payload['last_long_rest_at']).to be_present
    end

    it 'zera spell_slots_used inteiro' do
      sheet.runtime!.update!(spell_slots_used: { '1' => 2, '2' => 1, 'pact' => 1 })
      post "/api/v1/player/sheets/#{sheet.id}/runtime/long_rest", headers: headers
      expect(response.parsed_body['runtime_state']['spell_slots_used']).to eq({})
    end
  end

  # Alinha com `Api::V1::Player::SheetsController#sheets_scope_for_current_user`:
  # mestre site-wide edita ficha de outro jogador (`?dm=true`, sessão).
  context 'when requester is site DM' do
    let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
    let(:dm_user) { create(:user, role: dm_role) }
    let(:dm_headers) { bearer_headers_for(dm_user) }
    let(:other_user) { create(:user) }
    let(:other_character) { create(:character, user: other_user) }
    let!(:other_sheet) { create(:sheet, character: other_character) }

    it 'GET runtime encontra ficha de outro jogador' do
      get "/api/v1/player/sheets/#{other_sheet.id}/runtime", headers: dm_headers
      expect(response).to have_http_status(:ok)
    end

    it 'PATCH runtime persiste em ficha de outro jogador' do
      patch "/api/v1/player/sheets/#{other_sheet.id}/runtime",
            params: { runtime_state: { class_resources_used: { 'rage' => 1 } } },
            headers: dm_headers, as: :json
      expect(response).to have_http_status(:ok), -> { response.body }
      expect(response.parsed_body['runtime_state']['class_resources_used']['rage']).to eq(1)
    end
  end
end
