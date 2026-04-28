# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Player::SheetPreparedSpellsController', type: :request do
  let(:user) { create(:user) }
  let(:character) { create(:character, user: user) }
  let!(:sheet) { create(:sheet, character: character) }

  describe 'GET /api/v1/player/sheet_prepared_spells' do
    context 'when accessed by DM (not the sheet owner)' do
      let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
      let(:dm_user) { create(:user, role: dm_role) }
      let(:dm_headers) { bearer_headers_for(dm_user) }

      it 'lista preparadas da ficha alheia' do
        get '/api/v1/player/sheet_prepared_spells', params: { sheet_id: sheet.id }, headers: dm_headers

        expect(response).to have_http_status(:ok), -> { response.body }
        expect(response.parsed_body['sheet_prepared_spells']).to be_an(Array)
      end
    end
  end
end
