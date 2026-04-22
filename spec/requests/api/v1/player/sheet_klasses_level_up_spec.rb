# frozen_string_literal: true

require 'rails_helper'

# BDD — PATCH sheet_klasses dispara LevelUpService (persistência de nível + HP).
# Cobre hp_rolls opcional vs média automática.
RSpec.describe 'Api::V1::Player::SheetKlassesController level-up', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:race) { human_race }
  let(:sub_race) { human_standard_subrace(race) }
  let(:character) { create(:character, user: user, name: 'LvlUpSpec', status: :active) }
  let!(:barbarian_klass) do
    Klass.find_or_create_by!(api_index: 'barbarian') do |k|
      k.name = 'Bárbaro'
      k.hit_die = 12
      k.subclass_level = 3
    end
  end
  let!(:sheet) do
    create(
      :sheet,
      character: character,
      race: race,
      sub_race: sub_race,
      con: 14,
      hp_max: 14,
      hp_current: 14,
      current_level: 1,
      metadata: {
        'class_choices' => {
          'per_level' => {
            '1' => { 'skills' => %w[Atletismo Natureza] }
          }
        }
      }
    )
  end
  let!(:sheet_klass) { create(:sheet_klass, sheet: sheet, klass: barbarian_klass, level: 1) }

  describe 'A1 — PATCH level+1 com hp_rolls' do
    it 'A1.1 — aplica PV da rolagem explícita e sobe SheetKlass.level' do
      patch "/api/v1/player/sheet_klasses/#{sheet_klass.id}",
            params: { sheet_klass: { level: 2, hp_rolls: [12] } }.to_json,
            headers: headers.merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:ok)
      sheet_klass.reload
      sheet.reload
      expect(sheet_klass.level).to eq(2)
      # d12 roll 12 + CON +2 = 14 PV neste passo; hp_max era 14 → 28
      expect(sheet.hp_max).to eq(28)
      expect(sheet.current_level).to eq(2)
    end
  end

  describe 'A2 — PATCH level+1 sem hp_rolls (média)' do
    it 'A2.1 — usa ceil(hit_die/2)+CON (d12 → 6+2=8; hp_max 14→22)' do
      patch "/api/v1/player/sheet_klasses/#{sheet_klass.id}",
            params: { sheet_klass: { level: 2 } }.to_json,
            headers: headers.merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:ok)
      sheet.reload
      expect(sheet.hp_max).to eq(22)
    end
  end
end
