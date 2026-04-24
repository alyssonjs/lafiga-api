# frozen_string_literal: true

require 'rails_helper'

# Inventory + wallet for ?dm=true on character sheet: must allow role **DM**,
# not only literal `Admin` (authorize_site_wide_dm / Group.user_is_dm?).
RSpec.describe 'Api::V1::Admin::Sheet items + wallet for site-wide DM', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:dm_user) { create(:user, role: dm_role) }
  let(:player_user) { create(:user, role: player_role) }
  let(:dm_headers) { bearer_headers_for(dm_user) }
  let(:player_headers) { bearer_headers_for(player_user) }

  let(:race) { human_race }
  let(:sub_race) { human_standard_subrace(race) }
  let(:character) { create(:character, user: player_user, name: 'PC', background: 'Teste') }
  let!(:sheet) do
    create(
      :sheet,
      character: character,
      race: race,
      sub_race: sub_race,
      current_level: 1,
      str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10,
      hp_max: 10,
      hp_current: 10,
    )
  end

  describe 'GET /api/v1/admin/sheet_items' do
    it 'permite Mestre (papel DM) a listar itens de qualquer ficha' do
      get "/api/v1/admin/sheet_items?sheet_id=#{sheet.id}", headers: dm_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['sheet_items']).to be_a(Array)
    end

    it 'retorna 403 para jogador comum' do
      get "/api/v1/admin/sheet_items?sheet_id=#{sheet.id}", headers: player_headers

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /api/v1/admin/sheets/:id/wallet' do
    it 'permite Mestre (papel DM) a ler a carteira' do
      get "/api/v1/admin/sheets/#{sheet.id}/wallet", headers: dm_headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to have_key('wallet')
      expect(body).to have_key('coin_pouches')
    end

    it 'retorna 403 para jogador comum' do
      get "/api/v1/admin/sheets/#{sheet.id}/wallet", headers: player_headers

      expect(response).to have_http_status(:forbidden)
    end
  end
end
