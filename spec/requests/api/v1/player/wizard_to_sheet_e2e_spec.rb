# frozen_string_literal: true

require 'rails_helper'

# Phase 3.1 — End-to-end HTTP roundtrip (wizard → ficha)
#
# A Phase 3.0 (`character_sheet_summary_contract_spec`) chama o
# CharacterSheetSummaryService DIRETO, validando o `result` Ruby. Aqui
# subimos a stack inteira:
#
#   POST /api/v1/player/characters/provision  (header JWT → strong params →
#                                              CharacterProvisioningService)
#                              ⇩
#   GET  /api/v1/player/sheets/:id/summary?sync=true  (auth + render JSON)
#                              ⇩
#                       JSON.parse(response.body)
#
# Pega bugs que NÃO aparecem no service spec:
#   - Strong params dropando wizard.* sub-blocks
#   - Symbol keys virando string e quebrando consumer
#   - Middleware bloqueando algum content-type
#   - Auth header não respeitado
#   - Render dropando chaves (jbuilder, AMS, etc.)
RSpec.describe 'Wizard → Ficha (Phase 3.1 HTTP roundtrip)', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }

  # Mesmas chaves do Phase 3.0 contract spec, mas validadas no JSON
  # SERIALIZADO (todos os keys viram String, não Symbol).
  CONTRACT_KEYS = [
    %w[sheet name],
    %w[sheet hp_max],
    %w[sheet experience_points],
    %w[sheet alignment_index],
    %w[sheet race name],
    %w[abilities scores str],
    %w[abilities scores dex],
    %w[abilities scores con],
    %w[abilities scores int],
    %w[abilities scores wis],
    %w[abilities scores cha],
    %w[abilities sources],
    %w[movement speed_ft],
    %w[prof_bonus],
    %w[klasses],
    %w[proficiencies skills],
    %w[proficiencies languages],
    %w[proficiencies armor],
    %w[proficiencies weapons],
    %w[proficiencies tools],
    %w[saving_throws],
    %w[equipment ac ac],
    %w[equipment inventory],
    %w[equipment equipped],
    %w[conjuration ability],
    %w[features],
    %w[feats],
    %w[traits],
    %w[background],
    %w[runtime_state],
    %w[avatar_customization]
  ].freeze

  describe 'POST /provision → GET /sheets/:id/summary' do
    it 'devolve summary com todas as chaves do contract front-end' do
      race  = human_race
      sub   = human_standard_subrace(race)
      klass = barbarian_klass
      bg    = acolyte_background
      align = lawful_good_alignment

      payload = minimal_l1_barbarian_provision_payload(
        race: race, sub_race: sub, klass: klass, background: bg, alignment: align
      )

      # ---- 1) POST provision ------------------------------------------------
      post '/api/v1/player/characters/provision',
           params: payload, headers: headers, as: :json

      expect(response).to have_http_status(:created), -> { response.body }
      provision_json = response.parsed_body
      sheet_id = provision_json.dig('character', 'sheet_id')
      expect(sheet_id).to be_a(Integer), 'POST /provision não devolveu sheet_id'

      # ---- 2) GET summary ---------------------------------------------------
      get "/api/v1/player/sheets/#{sheet_id}/summary",
          params: { sync: 'true' }, headers: headers

      expect(response).to have_http_status(:ok), -> { response.body }
      expect(response.media_type).to eq('application/json')

      body = JSON.parse(response.body)
      expect(body).to have_key('summary'), "Resposta deve ter chave 'summary' top-level"
      summary = body['summary']
      expect(summary).to be_a(Hash)

      # ---- 3) Contract validation (mesmo set da Phase 3.0) ----------------
      missing = CONTRACT_KEYS.reject { |path| dig_present?(summary, path) }
      expect(missing).to eq([]),
        "Chaves AUSENTES no JSON HTTP serializado:\n  - #{missing.map { |p| p.join('.') }.join("\n  - ")}"
    end

    it 'GET sem auth devolve 401 (proteção do endpoint)' do
      get '/api/v1/player/sheets/1/summary'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'GET com auth de outro user devolve 404 (escopo @current_user.sheets)' do
      race  = human_race
      sub   = human_standard_subrace(race)
      klass = barbarian_klass
      bg    = acolyte_background
      align = lawful_good_alignment

      payload = minimal_l1_barbarian_provision_payload(
        race: race, sub_race: sub, klass: klass, background: bg, alignment: align
      )

      post '/api/v1/player/characters/provision',
           params: payload, headers: headers, as: :json
      sheet_id = response.parsed_body.dig('character', 'sheet_id')
      expect(sheet_id).to be_present

      other_user = create(:user)
      get "/api/v1/player/sheets/#{sheet_id}/summary",
          headers: bearer_headers_for(other_user)

      # `@current_user.sheets.find` lança RecordNotFound → 404 via ExceptionHandler
      expect(response.status).to be_in([404, 422]), -> {
        "Esperado 404/422 para acesso cross-user, got #{response.status}: #{response.body}"
      }
    end

    # Phase 3.1 — regressão HTTP do bug corrigido na Phase 3.0
    # ('escola-de-evocacao' => 'evocation' alias quebrado no
    # SubklassSlugResolver, que travava qualquer mago que escolhesse
    # Evocação no wizard).
    it 'wizard L2 que escolhe escola-de-evocacao via /provision sobe sem erro' do
      race  = human_race
      sub   = human_standard_subrace(race)
      klass = wizard_klass
      _sub_klass = wizard_evocation_subklass(klass)
      bg    = acolyte_background
      align = lawful_good_alignment

      payload = {
        character: { name: "RSpec Mago Evoc #{SecureRandom.hex(3)}", background: bg.name },
        wizard: {
          meta: { name: 'RSpec Mago Evoc', alignmentKey: align.api_index },
          race: {
            raceId: race.id, subRaceId: sub.id,
            ruleId: race.api_index, subRuleId: sub.api_index,
            attributes: { str: 8, dex: 14, con: 14, int: 16, wis: 12, cha: 10 },
            raceChoices: { chosenLanguages: [] }
          },
          klass: {
            klassId: klass.id, klassRuleSlug: 'wizard', level: 2,
            classSubclassId: 'escola-de-evocacao',
            classSkillPicks: %w[Arcanismo História],
            classPicksByLevel: {
              '1' => { 'hp' => { 'dieResult' => 6, 'total' => 8, 'method' => 'fixed' },
                       'skills' => %w[Arcanismo História] },
              '2' => { 'hp' => { 'dieResult' => 4, 'total' => 6, 'method' => 'fixed' } }
            }
          },
          background: { backgroundName: bg.name, backgroundKey: bg.api_index },
          equipment: {},
          avatar: { customization: {} }
        }
      }

      post '/api/v1/player/characters/provision',
           params: payload, headers: headers, as: :json

      expect(response).to have_http_status(:created), -> {
        body = response.body
        if body.include?('escola-de-evocacao') && body.include?('não encontrada')
          "REGRESSÃO Phase 3.0: alias 'escola-de-evocacao' => 'evocation' " \
          "voltou no SubklassSlugResolver. Body: #{body}"
        else
          body
        end
      }

      sheet_id = response.parsed_body.dig('character', 'sheet_id')
      expect(sheet_id).to be_present

      get "/api/v1/player/sheets/#{sheet_id}/summary",
          params: { sync: 'true' }, headers: headers
      expect(response).to have_http_status(:ok)
      summary = response.parsed_body['summary']
      klasses = summary['klasses']
      expect(klasses[0]['subclass']).to be_a(Hash),
        "summary.klasses[0].subclass deve ser populado após escolha L2 de Evocação"
      expect(klasses[0].dig('subclass', 'name')).to be_present
    end

    # Phase 4 — regressão HTTP dos 4 aliases quebrados achados na auditoria
    # ('berserker' que mapeava p/ inexistente, e 3 juramentos PT-BR de paladino
    # que mapeavam p/ 'oath_of_*' nunca seedados). Cada um quebrava o
    # LevelUpService no nível em que a subclasse é escolhida.
    {
      'barbarian L3 berserker'         => { klass: :barbarian_klass, sub_method: :barbarian_berserker_subklass, sub_id: 'berserker',                rule: 'barbarian', sub_at: 3 },
      'paladin L3 juramento-de-devocao' => { klass: :paladin_klass,   sub_method: :paladin_devotion_subklass,  sub_id: 'juramento-de-devocao',     rule: 'paladin',   sub_at: 3 }
    }.each do |label, conf|
      it "#{label} sobe sem erro via /provision (Phase 4 alias regression)" do
        race  = human_race
        sub   = human_standard_subrace(race)
        klass = send(conf[:klass])
        send(conf[:sub_method], klass) # garante SubKlass no DB
        bg    = acolyte_background
        align = lawful_good_alignment

        target_lv = conf[:sub_at]
        rows = (1..target_lv).each_with_object({}) do |lv, h|
          die = lv == 1 ? klass.hit_die : (klass.hit_die / 2 + 1)
          h[lv.to_s] = { 'hp' => { 'dieResult' => die, 'total' => die + 2, 'method' => 'fixed' } }
        end
        rows['1']['skills'] = %w[Atletismo Intimidação]
        # Escolhas obrigatórias por nível (fighting_style do Paladino no L2) — o
        # LevelUpGuard em modo estrito (RSpec) bloqueia o provision sem elas.
        (ClassRules.find(conf[:rule])&.dig(:required_choices_at_level) || {}).each do |lv, rc|
          next if lv.to_i > target_lv

          row = (rows[lv.to_s] ||= {})
          rc.each do |key, c|
            cnt = c[:choose].to_i
            next if cnt <= 0 || row.key?(key.to_s) || !c[:options].is_a?(Array)

            row[key.to_s] = c[:options].first(cnt)
          end
        end

        payload = {
          character: { name: "RSpec #{label} #{SecureRandom.hex(3)}", background: bg.name },
          wizard: {
            meta: { name: 'RSpec', alignmentKey: align.api_index },
            race: {
              raceId: race.id, subRaceId: sub.id,
              ruleId: race.api_index, subRuleId: sub.api_index,
              attributes: { str: 16, dex: 12, con: 14, int: 8, wis: 12, cha: 10 },
              raceChoices: { chosenLanguages: [] }
            },
            klass: {
              klassId: klass.id, klassRuleSlug: conf[:rule], level: target_lv,
              classSubclassId: conf[:sub_id],
              classSkillPicks: %w[Atletismo Intimidação],
              classPicksByLevel: rows
            },
            background: { backgroundName: bg.name, backgroundKey: bg.api_index },
            equipment: {},
            avatar: { customization: {} }
          }
        }

        post '/api/v1/player/characters/provision',
             params: payload, headers: headers, as: :json

        expect(response).to have_http_status(:created), -> {
          body = response.body
          if body.include?('SubKlass') && body.include?('não encontrada')
            "REGRESSÃO Phase 4: alias do SubklassSlugResolver mapeando para slug inexistente. Body: #{body}"
          else
            body
          end
        }
      end
    end

    it 'JSON serializado preserva tipos numéricos (não vira String)' do
      race  = human_race
      sub   = human_standard_subrace(race)
      klass = barbarian_klass
      bg    = acolyte_background
      align = lawful_good_alignment

      payload = minimal_l1_barbarian_provision_payload(
        race: race, sub_race: sub, klass: klass, background: bg, alignment: align
      )

      post '/api/v1/player/characters/provision',
           params: payload, headers: headers, as: :json
      sheet_id = response.parsed_body.dig('character', 'sheet_id')

      get "/api/v1/player/sheets/#{sheet_id}/summary",
          params: { sync: 'true' }, headers: headers
      summary = response.parsed_body['summary']

      # Numbers críticos para o front (UI faz aritmética com eles)
      expect(summary.dig('abilities', 'scores', 'str')).to be_a(Integer)
      expect(summary['prof_bonus']).to be_a(Integer)
      expect(summary.dig('movement', 'speed_ft')).to be_a(Integer)
      expect(summary.dig('equipment', 'ac', 'ac')).to be_a(Integer)
    end
  end

  # ----------- helpers -------------------------------------------------------

  def dig_present?(hash, path)
    node = hash
    path.each do |key|
      return false unless node.is_a?(Hash)
      node = node[key]
    end
    !node.nil?
  end
end
