# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Player::SheetKnownSpellsController', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user).merge('Content-Type' => 'application/json') }
  let(:wizard) { (Klass.find_by(api_index: 'wizard') || create(:klass, api_index: 'wizard', name: 'Mago Spec')) }
  let(:character) { create(:character, user: user) }
  let!(:sheet) { create(:sheet, character: character) }
  let!(:sk) { create(:sheet_klass, sheet: sheet, klass: wizard, level: 5) }
  let(:spell) { create(:spell, level: 1, name: 'Spec Grimo Del', api_index: "grdel_#{SecureRandom.hex(4)}") }

  describe 'DELETE /api/v1/player/sheet_known_spells/:id' do
    it 'remove magia com source grimoire e apaga preparada do mesmo spell_id' do
      ks = create(:sheet_known_spell, sheet_klass: sk, spell: spell, source: 'grimoire')
      SheetPreparedSpell.create!(sheet: sheet, spell: spell, auto: false, source: 'class')

      delete "/api/v1/player/sheet_known_spells/#{ks.id}?sheet_id=#{sheet.id}&klass_api_index=wizard",
             headers: headers

      expect(response).to have_http_status(:no_content)
      expect(SheetKnownSpell.find_by(id: ks.id)).to be_nil
      expect(SheetPreparedSpell.where(sheet_id: sheet.id, spell_id: spell.id).count).to eq(0)
    end

    it 'recusa remover magia que não é grimoire' do
      ks = create(:sheet_known_spell, sheet_klass: sk, spell: spell, source: 'class')

      delete "/api/v1/player/sheet_known_spells/#{ks.id}?sheet_id=#{sheet.id}&klass_api_index=wizard",
             headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(SheetKnownSpell.find_by(id: ks.id)).to be_present
    end

    context 'when accessed by DM (not the sheet owner)' do
      let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
      let(:dm_user) { create(:user, role: dm_role) }
      let(:dm_headers) { bearer_headers_for(dm_user).merge('Content-Type' => 'application/json') }

      it 'permite remover magia grimoire' do
        ks = create(:sheet_known_spell, sheet_klass: sk, spell: spell, source: 'grimoire')

        delete "/api/v1/player/sheet_known_spells/#{ks.id}?sheet_id=#{sheet.id}&klass_api_index=wizard",
               headers: dm_headers

        expect(response).to have_http_status(:no_content)
        expect(SheetKnownSpell.find_by(id: ks.id)).to be_nil
      end

      it 'permite expandir grimório (POST grimoire)' do
        post '/api/v1/player/sheet_known_spells',
             params: {
               sheet_id: sheet.id,
               klass_api_index: 'wizard',
               spell_id: spell.id,
               grimoire_expansion: true,
             }.to_json,
             headers: dm_headers

        expect(response).to have_http_status(:created), -> { response.body }
        expect(SheetKnownSpell.exists?(sheet_klass_id: sk.id, spell_id: spell.id, source: 'grimoire')).to be(true)
      end
    end
  end
end
