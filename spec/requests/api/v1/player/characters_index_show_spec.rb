# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Player::CharactersController index & show', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }

  let(:race) { human_race }
  let(:sub_race) { human_standard_subrace(race) }
  let(:character) { create(:character, user: user, name: 'Listado', background: 'Teste') }
  let!(:sheet) do
    create(
      :sheet,
      character: character,
      race: race,
      sub_race: sub_race,
      current_level: 7,
      metadata: { 'current_level' => 7 }
    )
  end
  let!(:sheet_klass) { create(:sheet_klass, sheet: sheet, level: 7) }

  describe 'GET /api/v1/player/characters' do
    it 'expõe pending_dm_level_up quando existe unlock' do
      dm_role = Role.find_by(name: 'DM') || create(:role, name: 'DM')
      dm = create(:user, role: dm_role)
      CharacterDmLevelUnlock.create!(character: character, unlocked_by_user: dm)
      get '/api/v1/player/characters', headers: headers
      row = response.parsed_body['characters'].find { |c| c['id'] == character.id }
      expect(row['pending_dm_level_up']).to be true
    end

    it 'returns main_class.name and sheet.race.name for each character' do
      get '/api/v1/player/characters', headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['characters']).to be_an(Array)
      row = json['characters'].find { |c| c['id'] == character.id }
      expect(row).to be_present
      expect(row.dig('main_class', 'name')).to eq('Bárbaro')
      expect(row.dig('sheet', 'race', 'name')).to eq('Humano')
    end

    it 'expõe metadata no list payload (necessário para sheetMetadata no front)' do
      # `metadata` foi promovido para SHEET_LIST_COLUMNS para permitir que o front
      # construa Character.sheetMetadata a partir do list endpoint (snacks, expertise).
      sheet.update!(metadata: { 'foo' => 'bar' }, class_choices: { 'x' => 1 })
      get '/api/v1/player/characters', headers: headers

      expect(response).to have_http_status(:ok)
      row = response.parsed_body['characters'].find { |c| c['id'] == character.id }
      expect(row.dig('sheet', 'metadata')).to eq({ 'foo' => 'bar' })
      # `class_choices` continua fora do slim para reduzir payload — front lê via metadata.
      expect(row.dig('sheet', 'class_choices')).to be_nil
      expect(row.dig('sheet', 'id')).to eq(sheet.id)
    end

    it 'expõe metadata.class_choices.per_level (snacks/expertise) para o Cozinheiro' do
      sheet.update!(metadata: {
        'class_choices' => {
          'per_level' => {
            '1' => { 'snack' => %w[cook-snack-cha-verde cook-snack-leite], 'skills' => %w[Atuação Natureza] },
            '2' => { 'expertise_skills' => %w[Percepção Atuação] }
          }
        }
      })
      get '/api/v1/player/characters', headers: headers

      expect(response).to have_http_status(:ok)
      row = response.parsed_body['characters'].find { |c| c['id'] == character.id }
      meta = row.dig('sheet', 'metadata') || {}
      per_level = meta.dig('class_choices', 'per_level') || {}
      expect(per_level.dig('1', 'snack')).to include('cook-snack-cha-verde')
      expect(per_level.dig('2', 'expertise_skills')).to include('Percepção')
    end
  end

  describe 'GET /api/v1/player/characters/:id' do
    it 'returns main_class with name, api_index, hit_die' do
      get "/api/v1/player/characters/#{character.id}", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      mc = json.dig('character', 'main_class')
      expect(mc['name']).to eq('Bárbaro')
      expect(mc['api_index']).to eq('barbarian')
      expect(mc['hit_die']).to eq(12)
      meta = json.dig('character', 'sheet', 'metadata')
      expect(meta).to be_a(Hash)
    end
  end
end
