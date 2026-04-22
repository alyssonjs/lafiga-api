# frozen_string_literal: true

require 'rails_helper'
require 'json'

# Phase 2 — Resilience test
#
# Pega todas as fichas reais extraídas das planilhas XLSX da campanha LaFiga
# (api/docs/imported_sheets.json — 35 auditáveis, 4 skipped) e tenta provisioná-las
# end-to-end via CharacterProvisioningService. O objetivo é validar que toda
# combinação real (race + subrace + class + subclass + ability_scores) que apareceu
# em jogo é aceita pelo nosso pipeline de criação.
#
# Phase 2.0 (este arquivo): provisiona em LEVEL 1 (smoke test).
# Phase 2.1 (futuro): subir até o level real da ficha via classPicksByLevel /
#   LevelUpService — exige seed completo (sub_klass_levels, features etc).
#
# Estratégia para falhas:
#   - Cada ficha vira um exemplo isolado (it ... do).
#   - Falhas viram mensagens estruturadas que dizem QUAL ficha quebrou e
#     POR QUE (cmd.errors.full_messages).
#   - Não usamos `aggregate_failures` para que cada exception fique nominal
#     no output do RSpec.
RSpec.describe 'Imported XLSX sheets — provisioning resilience', type: :service do
  let(:user) { create(:user) }
  let(:default_bg)    { Background.find_by(api_index: 'soldier') || Background.first }
  let(:default_align) { Alignment.find_by(api_index: 'n')        || Alignment.first  }

  before(:all) do
    # Seed todo o catálogo PHB+alternativas conhecidas pelo projeto antes da
    # primeira ficha. Find_or_create_by garante idempotência.
    ImportedSheetsSeeder.seed_all!
  end

  # --------- helpers --------------------------------------------------------

  def ability_score(sheet, key)
    val = sheet.dig('abilities', key, 'score') ||
          sheet.dig('abilities', key)
    val.is_a?(Numeric) ? val.to_i : val.to_i.nonzero? || 10
  end

  def build_payload(sheet)
    meta  = sheet['meta']  || {}
    race  = meta['race']   || {}
    klass = meta['klass']  || {}

    base_attrs = {
      'str' => ability_score(sheet, 'strength'),
      'dex' => ability_score(sheet, 'dexterity'),
      'con' => ability_score(sheet, 'constitution'),
      'int' => ability_score(sheet, 'intelligence'),
      'wis' => ability_score(sheet, 'wisdom'),
      'cha' => ability_score(sheet, 'charisma')
    }

    klass_record = Klass.find_by(api_index: klass['class_api_index'])
    hd           = klass_record&.hit_die.to_i.nonzero? || 8
    con_mod      = (base_attrs['con'] - 10) / 2
    hp_total     = [hd + con_mod, 1].max

    char_name = "#{meta['name'] || sheet['tab_name']}-RSpec-#{SecureRandom.hex(2)}"

    {
      character: { name: char_name, background: default_bg.name },
      wizard: {
        meta: { name: meta['name'] || sheet['tab_name'], alignmentKey: default_align.api_index },
        race: {
          ruleId:     race['race_api_index'],
          subRuleId:  race['subrace_api_index'],
          attributes: base_attrs,
          raceChoices: { chosenLanguages: [] }
        },
        klass: {
          klassRuleSlug: klass['class_api_index'],
          level: 1, # Phase 2.0 baseline
          classSkillPicks: %w[Atletismo Intimidação],
          classPicksByLevel: {
            '1' => { 'hp' => { 'dieResult' => hd, 'total' => hp_total, 'method' => 'fixed' } }
          }
        },
        background: {
          backgroundName: default_bg.name,
          backgroundKey:  default_bg.api_index
        },
        equipment: {},
        avatar:    { customization: {} }
      }
    }
  end

  # --------- generate one example per imported sheet ------------------------

  ImportedSheetsSeeder.auditable_sheets.each do |sheet|
    tab     = sheet['tab_name']
    race_ai = sheet.dig('meta', 'race',  'race_api_index')
    cls_ai  = sheet.dig('meta', 'klass', 'class_api_index')

    it "provisiona '#{tab}' (#{race_ai}/#{cls_ai}) em level 1 via CharacterProvisioningService" do
      payload = build_payload(sheet)
      cmd     = CharacterProvisioningService.call(user: user, payload: payload)

      expect(cmd.success?).to be(true), -> {
        msgs = cmd.errors.full_messages.join('; ') rescue cmd.inspect
        "[#{tab}] payload=#{race_ai}/#{cls_ai} falhou: #{msgs}"
      }

      sheet_record = Sheet.order(:id).last
      expect(sheet_record).to be_present
      expect(sheet_record.metadata).to be_a(Hash)
      expect(sheet_record.metadata['current_level']).to eq(1)
      expect(sheet_record.metadata.dig('class_choices', 'per_level', '1', 'hp', 'total')).to be_present
    end
  end
end
