# frozen_string_literal: true

require 'rails_helper'

# BDD: Criação de personagem com a raça Tiefling (HOUSERULES Lafiga)
# -------------------------------------------------------------------
# FONTE CANÔNICA: `~/Documents/MF/Atualizacao_das_Racas.pdf` (campanha Lafiga).
# NÃO é PHB puro — é uma extensão local que divide o legado infernal em
# 3 sub-raças (Abissal, Ctônico, Infernal). O `api/config/race_rules.yml`
# implementa exatamente essas houserules. Não tratar como divergência.
#
# Regras (PDF Lafiga, p. 3-4):
#
#   Tiefling (base):
#     - Médio, 9 m (30 ft), Visão no Escuro 18 m (60 ft)
#     - Idiomas: Comum, Infernal
#     - ASI: +1 INT, +2 CHA
#     - Cantrip Taumaturgia (sempre disponível, ability=CHA)
#     - Sem resistência intrínseca à raça base — vai para sub-raça
#     - Magias do legado: 3º e 5º nível (1x/descanso longo, ability=CHA),
#       definidas pela sub-raça
#
#   Sub-raças:
#     | Sub-raça   | Resistência | Magia nv 3            | Magia nv 5             |
#     |------------|-------------|-----------------------|------------------------|
#     | abissal    | Veneno      | Raio Adoecente        | Cativar                |
#     | ctonico    | Necrótico   | Vitalidade Falsa      | Raio do Enfraquecimento|
#     | infernal   | Fogo        | Repreensão Infernal   | Escuridão              |
#
# YAML (`api/config/race_rules.yml:465-508`):
#   - Base: ASI INT+1/CHA+2, langs always [Comum, Infernal], darkvision 60,
#     traits [darkvision, thaumaturgy_cantrip] (com grants.spells thaumaturgy)
#   - Sub-raças com `legacy_resistance_*` e `*_legacy*` traits (que carregam
#     as magias progressivas via trait_definitions).
RSpec.describe 'Criação de Personagem Tiefling (Houserules Lafiga)', type: :service do
  let(:user) { create(:user) }

  let!(:tiefling_race) do
    Race.find_or_create_by!(api_index: 'tiefling') { |r| r.name = 'Tiefling' }
  end

  let!(:abissal_subrace) do
    SubRace.find_or_create_by!(race_id: tiefling_race.id, api_index: 'abissal') do |s|
      s.name = 'Abissal'
    end
  end

  let!(:ctonico_subrace) do
    SubRace.find_or_create_by!(race_id: tiefling_race.id, api_index: 'ctonico') do |s|
      s.name = 'Ctônico'
    end
  end

  let!(:infernal_subrace) do
    SubRace.find_or_create_by!(race_id: tiefling_race.id, api_index: 'infernal') do |s|
      s.name = 'Infernal'
    end
  end

  let!(:klass) do
    Klass.find_or_create_by!(api_index: 'warlock') do |k|
      k.name = 'Bruxo'; k.hit_die = 8; k.subclass_level = 1
    end
  end

  let!(:bg) do
    Background.find_or_create_by!(api_index: 'charlatan') do |b|
      b.name = 'Charlatão'; b.feature_name = 'Identidade Falsa'; b.feature_desc = 'Spec'
    end
  end

  let!(:align) do
    Alignment.find_or_create_by!(api_index: 'cn') { |a| a.name = 'Caótico e Neutro' }
  end

  # Spells citadas no YAML (api_index sem acento, kebab/snake conforme o YAML).
  # Criamos com api_index canônico para o RacialSpellsService casar.
  let!(:thaumaturgy_spell) do
    Spell.find_or_create_by!(api_index: 'thaumaturgy') do |s|
      s.name = 'Taumaturgia'; s.level = 0
    end
  end

  # Base 11/12/12/13/10/14. Tiefling = +INT 1, +CHA 2 → 11/12/12/14/10/16.
  def base_attrs
    { str: 11, dex: 12, con: 12, int: 13, wis: 10, cha: 14 }
  end

  def post_racial
    base_attrs.merge(int: base_attrs[:int] + 1, cha: base_attrs[:cha] + 2)
  end

  def sub_id_for(sub_rule)
    {
      'abissal' => abissal_subrace.id,
      'ctonico' => ctonico_subrace.id,
      'infernal' => infernal_subrace.id
    }[sub_rule]
  end

  def build_payload(sub_rule:)
    {
      character: { name: "Spec Tief #{sub_rule} #{SecureRandom.hex(3)}", background: bg.name },
      wizard: {
        meta: { name: "Spec Tief #{sub_rule}", alignmentKey: align.api_index },
        race: {
          raceId: tiefling_race.id,
          subRaceId: sub_id_for(sub_rule),
          ruleId: 'tiefling',
          subRuleId: sub_rule,
          attributes: post_racial,
          raceChoices: {}
        },
        klass: {
          klassId: klass.id,
          level: 1,
          classSkillPicks: %w[Enganação Persuasão],
          classPicksByLevel: { '1' => { 'hp' => { 'dieResult' => 8, 'total' => 9, 'method' => 'average' } } }
        },
        background: { backgroundName: bg.name, backgroundKey: bg.api_index },
        equipment: {},
        avatar: { customization: {} }
      }
    }
  end

  before { RaceRules.reload! }

  # =====================================================================
  #  Provisioning — base do Tiefling (constante entre sub-raças)
  # =====================================================================
  describe 'CharacterProvisioningService — Tiefling (base; verifica via Infernal)' do
    let(:payload) { build_payload(sub_rule: 'infernal') }

    it 'persiste race_id, sub_race_id, speed=30 e idiomas Comum/Infernal' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }
      sheet = Sheet.order(:id).last

      expect(sheet.race_id).to eq(tiefling_race.id)
      expect(sheet.sub_race_id).to eq(infernal_subrace.id)
      rs = sheet.race_summary || {}
      expect(rs['speed_ft'].to_i).to eq(30)
      langs = Array(rs['languages']).map(&:to_s)
      expect(langs).to include('Comum', 'Infernal')
      expect(langs.size).to eq(2)
    end

    it 'reflete +1 INT e +2 CHA nas colunas (constante entre sub-raças)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect(sheet.int).to eq(base_attrs[:int] + 1)
      expect(sheet.cha).to eq(base_attrs[:cha] + 2)
      # ASI base não toca em STR/DEX/CON/WIS:
      expect(sheet.str).to eq(base_attrs[:str])
      expect(sheet.dex).to eq(base_attrs[:dex])
      expect(sheet.con).to eq(base_attrs[:con])
      expect(sheet.wis).to eq(base_attrs[:wis])
    end

    it 'cria SheetKnownSpell para Taumaturgia (cantrip racial base, ability=CHA, at_will)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      ksk = sheet.sheet_klasses.first
      racial = SheetKnownSpell.where(sheet_klass: ksk, source: 'race').to_a
      names = racial.map { |s| s.spell&.api_index.to_s }
      expect(names).to include('thaumaturgy'),
        'Tiefling base concede Taumaturgia como cantrip racial (PDF Lafiga p. 3, "Presença Sobrenatural").'
    end
  end

  # =====================================================================
  #  Provisioning — Abissal (Resistência Veneno)
  # =====================================================================
  describe 'CharacterProvisioningService — Tiefling Abissal' do
    let(:payload) { build_payload(sub_rule: 'abissal') }

    it 'persiste sub_race_id Abissal e sub_race_name correto' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect(sheet.sub_race_id).to eq(abissal_subrace.id)
      expect(sheet.race_summary['sub_race_name']).to eq('Abissal')
    end

    it 'RaceRules.apply: traits incluem legacy_resistance_poison e abyssal_legacy' do
      applied = RaceRules.apply(race_id: 'tiefling', subrace_id: 'abissal', choices: {})
      keys = Array(applied[:traits]).map { |t| t[:key] || t['key'] }
      expect(keys).to include('thaumaturgy_cantrip', 'legacy_resistance_poison', 'abyssal_legacy')
      # Não pode incluir resistências/legados das outras sub-raças:
      expect(keys).not_to include('legacy_resistance_fire', 'legacy_resistance_necrotic')
      expect(keys).not_to include('infernal_legacy_variant', 'chthonic_legacy')
    end
  end

  # =====================================================================
  #  Provisioning — Ctônico (Resistência Necrótico)
  # =====================================================================
  describe 'CharacterProvisioningService — Tiefling Ctônico' do
    let(:payload) { build_payload(sub_rule: 'ctonico') }

    it 'persiste sub_race_id Ctônico e sub_race_name correto' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect(sheet.sub_race_id).to eq(ctonico_subrace.id)
      expect(sheet.race_summary['sub_race_name']).to eq('Ctônico')
    end

    it 'RaceRules.apply: traits incluem legacy_resistance_necrotic e chthonic_legacy' do
      applied = RaceRules.apply(race_id: 'tiefling', subrace_id: 'ctonico', choices: {})
      keys = Array(applied[:traits]).map { |t| t[:key] || t['key'] }
      expect(keys).to include('thaumaturgy_cantrip', 'legacy_resistance_necrotic', 'chthonic_legacy')
      expect(keys).not_to include('legacy_resistance_fire', 'legacy_resistance_poison')
      expect(keys).not_to include('infernal_legacy_variant', 'abyssal_legacy')
    end
  end

  # =====================================================================
  #  Provisioning — Infernal (Resistência Fogo, "PHB clássico")
  # =====================================================================
  describe 'CharacterProvisioningService — Tiefling Infernal' do
    let(:payload) { build_payload(sub_rule: 'infernal') }

    it 'persiste sub_race_id Infernal e sub_race_name correto' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect(sheet.sub_race_id).to eq(infernal_subrace.id)
      expect(sheet.race_summary['sub_race_name']).to eq('Infernal')
    end

    it 'RaceRules.apply: traits incluem legacy_resistance_fire e infernal_legacy_variant' do
      applied = RaceRules.apply(race_id: 'tiefling', subrace_id: 'infernal', choices: {})
      keys = Array(applied[:traits]).map { |t| t[:key] || t['key'] }
      expect(keys).to include('thaumaturgy_cantrip', 'legacy_resistance_fire', 'infernal_legacy_variant')
      expect(keys).not_to include('legacy_resistance_necrotic', 'legacy_resistance_poison')
      expect(keys).not_to include('chthonic_legacy', 'abyssal_legacy')
    end
  end

  # =====================================================================
  #  Tabela — resistência por sub-raça (auditoria PDF)
  # =====================================================================
  describe 'Auditoria PDF Lafiga: resistência de legado por sub-raça' do
    {
      'abissal'  => 'poison',
      'ctonico'  => 'necrotic',
      'infernal' => 'fire'
    }.each do |sub_rule, expected_damage_key|
      it "#{sub_rule} concede resistência ao tipo correto (legacy_resistance_#{expected_damage_key})" do
        applied = RaceRules.apply(race_id: 'tiefling', subrace_id: sub_rule, choices: {})
        keys = Array(applied[:traits]).map { |t| t[:key] || t['key'] }
        expect(keys).to include("legacy_resistance_#{expected_damage_key}"),
          "Sub-raça #{sub_rule} deve trazer legacy_resistance_#{expected_damage_key} " \
          "(PDF Lafiga p. 4); veio traits=#{keys.inspect}"
      end
    end
  end

  # =====================================================================
  #  RaceRules.apply — contrato canônico do YAML (= contrato Lafiga)
  # =====================================================================
  describe 'RaceRules.apply — base canônica do Tiefling' do
    it 'speed=30, darkvision=60, ASI INT+1/CHA+2, langs Comum/Infernal' do
      applied = RaceRules.apply(race_id: 'tiefling', subrace_id: nil, choices: {})
      expect(applied[:speed]).to eq(30)
      dv = applied[:darkvision]
      val = dv.is_a?(Hash) ? (dv[:range] || dv['range']) : dv
      expect(val.to_i).to eq(60)
      expect(applied[:languages]).to include('Comum', 'Infernal')

      ability = applied[:ability] || {}
      increases = ability[:increases] || ability['increases'] || []
      pairs = increases.map { |e| [(e[:ability] || e['ability']).to_s, (e[:amount] || e['amount']).to_i] }
      expect(pairs).to include(['INT', 1], ['CHA', 2])
    end

    it 'base sempre concede Taumaturgia (cantrip) via thaumaturgy_cantrip trait' do
      applied = RaceRules.apply(race_id: 'tiefling', subrace_id: nil, choices: {})
      keys = Array(applied[:traits]).map { |t| t[:key] || t['key'] }
      expect(keys).to include('thaumaturgy_cantrip')

      spells = Array(applied[:innate_spells]).map { |s| (s[:name] || s['name']).to_s }
      expect(spells).to include('thaumaturgy')
    end
  end

  # =====================================================================
  #  GAPs do sistema
  # =====================================================================
  describe 'CPS persiste darkvision em race_summary' do
    it 'darkvision=60 para Tiefling Infernal' do
      cmd = CharacterProvisioningService.call(user: user, payload: build_payload(sub_rule: 'infernal'))
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect((sheet.race_summary || {})['darkvision'].to_i).to eq(60)
    end
  end
end
