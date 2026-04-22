# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../../support/imported_sheets_payload_builder'
require_relative '../../../../support/imported_sheets_spell_seeder'

# Phase 7 (passo 3) — Roundtrip HTTP completo sobre fichas REAIS importadas
#
# Phase 3.1 só rodou via HTTP com bárbaro sintético. Esta spec exercita
# 3 fichas reais representativas via o fluxo COMPLETO:
#
#   POST /api/v1/player/characters/provision  → JSON serializado
#   GET  /api/v1/player/sheets/:id/summary    → JSON serializado
#
# Pega bugs que o spec de service direto NÃO pega:
#   - Acentos PT-BR no nome do personagem ou ficha (encoding)
#   - Strong params dropando blocos do payload importado
#   - Chaves com símbolos virando string (e front quebrando)
#   - Render dropando campos opcionais
RSpec.describe 'Imported sheets — HTTP roundtrip (Phase 7)', type: :request do
  include AuthHelpers

  before(:all) do
    ImportedSheetsSeeder.seed_all!
    ImportedSheetsSpellSeeder.seed_all!
  end

  let(:user)    { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:bg)     { Background.find_by(api_index: 'soldier') || Background.first }
  let(:align)  { Alignment.find_by(api_index: 'n')        || Alignment.first  }

  # Fichas escolhidas por cobertura de cadeias críticas:
  PERSONAS = %w[
    Allan
    Shanti
    Caio
  ].freeze
  # Allan  → fighter L7 / cavaleiro-arcano (third-caster INT)
  # Shanti → cleric L5 / dominio-da-vida   (full caster prepared)
  # Caio   → rogue L9  / cacador-de-tesouros (non-caster, melee skill-heavy)

  CONTRACT_KEYS = [
    %w[sheet name], %w[sheet hp_max], %w[sheet experience_points],
    %w[abilities scores str], %w[abilities scores dex], %w[abilities scores con],
    %w[abilities scores int], %w[abilities scores wis], %w[abilities scores cha],
    %w[abilities sources], %w[movement speed_ft], %w[prof_bonus],
    %w[klasses], %w[proficiencies skills], %w[proficiencies languages],
    %w[proficiencies armor], %w[proficiencies weapons], %w[proficiencies tools],
    %w[saving_throws], %w[equipment ac ac], %w[equipment inventory],
    %w[equipment equipped], %w[features], %w[feats], %w[traits],
    %w[background], %w[runtime_state], %w[avatar_customization]
  ].freeze

  def dig_present?(hash, path)
    node = hash
    path.each do |k|
      return false unless node.is_a?(Hash) && node.key?(k)
      node = node[k]
    end
    !node.nil?
  end

  PERSONAS.each do |tab|
    sheet_data = ImportedSheetsSeeder.auditable_sheets.find { |s| s['tab_name'] == tab }

    it "[#{tab}] roundtrip completo POST /provision → GET /summary mantém contract" do
      skip "Ficha #{tab} não encontrada em imported_sheets.json" unless sheet_data

      payload = ImportedSheetsPayloadBuilder.build(
        sheet_data, user: user, background: bg, alignment: align
      )

      # POST /provision
      post '/api/v1/player/characters/provision',
           params: payload, headers: headers, as: :json
      expect(response).to have_http_status(:created), -> {
        "POST /provision falhou para #{tab}: #{response.body}"
      }

      pj = response.parsed_body
      sheet_id = pj.dig('character', 'sheet_id') || pj.dig('character', 'sheet', 'id')
      expect(sheet_id).to be_a(Integer), "sheet_id ausente no POST /provision response"

      # GET /summary
      get "/api/v1/player/sheets/#{sheet_id}/summary",
          params: { sync: 'true' }, headers: headers
      expect(response).to have_http_status(:ok), -> {
        "GET /summary falhou para #{tab}: #{response.body}"
      }
      expect(response.media_type).to eq('application/json')

      body    = JSON.parse(response.body)
      summary = body['summary']
      expect(summary).to be_a(Hash)

      missing = CONTRACT_KEYS.reject { |path| dig_present?(summary, path) }
      expect(missing).to eq([]), -> {
        "[#{tab}] Chaves AUSENTES no JSON HTTP serializado:\n  - " +
          missing.map { |p| p.join('.') }.join("\n  - ")
      }

      # Tipos numéricos não viraram String no caminho HTTP
      expect(summary.dig('abilities', 'scores', 'str')).to be_a(Integer)
      expect(summary.dig('prof_bonus')).to be_a(Integer)
      expect(summary.dig('movement', 'speed_ft')).to be_a(Integer)
      expect(summary.dig('equipment', 'ac', 'ac')).to be_a(Integer)

      # Validação específica por categoria
      class_idx = sheet_data.dig('meta', 'klass', 'class_api_index')
      sub_idx   = sheet_data.dig('meta', 'klass', 'subclass_api_index')
      level     = ImportedSheetsPayloadBuilder.target_level_for(sheet_data)

      klasses = summary['klasses']
      expect(klasses).to be_a(Array).and(be_present)
      expect(klasses.first['name']).to be_a(String)
      expect(klasses.first['level']).to eq(level)

      # Third-caster: ability deve ser INT
      if class_idx == 'fighter' && sub_idx == 'cavaleiro-arcano' && level >= 3
        expect(summary.dig('conjuration', 'ability').to_s.upcase).to eq('INT'),
          "EK deveria ter conjuration.ability=INT, got #{summary.dig('conjuration', 'ability').inspect}"
      end

      # Full caster: deve ter spell_save_dc numérico
      if %w[cleric druid wizard sorcerer bard warlock].include?(class_idx)
        expect(summary.dig('conjuration', 'spell_save_dc')).to be_a(Integer),
          "Caster #{class_idx} L#{level} sem spell_save_dc"
      end
    end
  end
end
