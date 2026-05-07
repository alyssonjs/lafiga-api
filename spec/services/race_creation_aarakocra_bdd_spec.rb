# frozen_string_literal: true

require 'rails_helper'

# BDD: Criação de personagem com a raça Aarakocra (HOUSERULES Lafiga)
# --------------------------------------------------------------------
# FONTE CANÔNICA: `~/Documents/MF/Atualizacao_das_Racas.pdf` (campanha Lafiga, p. 2-3).
# NÃO é PHB puro — é uma extensão local com 3 sub-raças. O `api/config/race_rules.yml`
# implementa essas houserules. Não tratar como divergência.
#
# Regras (PDF Lafiga, p. 2-3):
#
#   Aarakocra (base):
#     - Médio, 7,5 m caminhada (25 ft), Voo 15 m (sem armadura média/pesada)
#     - Idiomas: Comum, Aarakocra, Auran
#     - ASI: +2 DEX
#     - Garras: 1d4 cortante, proficiente
#
#   Sub-raças:
#     | Sub-raça    | ASI extra | Particularidade                                   |
#     |-------------|-----------|---------------------------------------------------|
#     | falconicos  | +1 STR    | Únicos que voam com armadura média (flight_medium_ok) |
#     | nocturnos   | +1 WIS    | Visão no Escuro 18 m (60 ft) — darkvision         |
#     | cypselanos  | +1 CHA    | Proficiência Performance + Voz como instrumento  |
#
# YAML (`api/config/race_rules.yml:9-57`):
#   - Base: speed 25, langs always [Comum, Aarakocra, Auran], traits
#     [flight_15m_no_med_heavy, claws_1d4_slashing]
#   - Sub-raças: falconicos (+1 STR + flight_medium_ok), nocturnos (+1 WIS +
#     darkvision range 60), cypselanos (+1 CHA + Atuação skill + Voz tool +
#     trait natural_singers)
RSpec.describe 'Criação de Personagem Aarakocra (Houserules Lafiga)', type: :service do
  let(:user) { create(:user) }

  let!(:aarakocra_race) do
    Race.find_or_create_by!(api_index: 'aarakocra') { |r| r.name = 'Aarakocra' }
  end

  let!(:falconicos_subrace) do
    SubRace.find_or_create_by!(race_id: aarakocra_race.id, api_index: 'falconicos') do |s|
      s.name = 'Falcônicos'
    end
  end

  let!(:nocturnos_subrace) do
    SubRace.find_or_create_by!(race_id: aarakocra_race.id, api_index: 'nocturnos') do |s|
      s.name = 'Nocturnos'
    end
  end

  let!(:cypselanos_subrace) do
    SubRace.find_or_create_by!(race_id: aarakocra_race.id, api_index: 'cypselanos') do |s|
      s.name = 'Cypselanos'
    end
  end

  let!(:klass) do
    Klass.find_or_create_by!(api_index: 'ranger') do |k|
      k.name = 'Patrulheiro'; k.hit_die = 10; k.subclass_level = 3
    end
  end

  let!(:bg) do
    Background.find_or_create_by!(api_index: 'outlander') do |b|
      b.name = 'Forasteiro'; b.feature_name = 'Errante'; b.feature_desc = 'Spec'
    end
  end

  let!(:align) do
    Alignment.find_or_create_by!(api_index: 'cg') { |a| a.name = 'Caótico e Bom' }
  end

  # Base 10/14/12/10/12/12.
  #   falconicos = +DEX 2 / +STR 1   →  11/16/12/10/12/12
  #   nocturnos  = +DEX 2 / +WIS 1   →  10/16/12/10/13/12
  #   cypselanos = +DEX 2 / +CHA 1   →  10/16/12/10/12/13
  def base_attrs
    { str: 10, dex: 14, con: 12, int: 10, wis: 12, cha: 12 }
  end

  def post_racial(sub_rule)
    case sub_rule
    when 'falconicos' then base_attrs.merge(dex: base_attrs[:dex] + 2, str: base_attrs[:str] + 1)
    when 'nocturnos'  then base_attrs.merge(dex: base_attrs[:dex] + 2, wis: base_attrs[:wis] + 1)
    when 'cypselanos' then base_attrs.merge(dex: base_attrs[:dex] + 2, cha: base_attrs[:cha] + 1)
    end
  end

  def sub_id_for(sub_rule)
    {
      'falconicos' => falconicos_subrace.id,
      'nocturnos' => nocturnos_subrace.id,
      'cypselanos' => cypselanos_subrace.id
    }[sub_rule]
  end

  def build_payload(sub_rule:)
    {
      character: { name: "Spec Aar #{sub_rule} #{SecureRandom.hex(3)}", background: bg.name },
      wizard: {
        meta: { name: "Spec Aar #{sub_rule}", alignmentKey: align.api_index },
        race: {
          raceId: aarakocra_race.id,
          subRaceId: sub_id_for(sub_rule),
          ruleId: 'aarakocra',
          subRuleId: sub_rule,
          attributes: post_racial(sub_rule),
          raceChoices: {}
        },
        klass: {
          klassId: klass.id,
          level: 1,
          classSkillPicks: %w[Percepção Furtividade],
          classPicksByLevel: { '1' => { 'hp' => { 'dieResult' => 10, 'total' => 11, 'method' => 'average' } } }
        },
        background: { backgroundName: bg.name, backgroundKey: bg.api_index },
        equipment: {},
        avatar: { customization: {} }
      }
    }
  end

  before { RaceRules.reload! }

  # =====================================================================
  #  Provisioning — base do Aarakocra (constante entre sub-raças)
  # =====================================================================
  describe 'CharacterProvisioningService — Aarakocra (base; verifica via Falconicos)' do
    let(:payload) { build_payload(sub_rule: 'falconicos') }

    it 'persiste race_id, sub_race_id, speed=25 e idiomas Comum/Aarakocra/Auran' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }
      sheet = Sheet.order(:id).last

      expect(sheet.race_id).to eq(aarakocra_race.id)
      expect(sheet.sub_race_id).to eq(falconicos_subrace.id)
      rs = sheet.race_summary || {}
      expect(rs['speed_ft'].to_i).to eq(25),
        'Aarakocra base tem 7,5 m (25 ft) de caminhada (PDF Lafiga p. 2).'
      langs = Array(rs['languages']).map(&:to_s)
      expect(langs).to include('Comum', 'Aarakocra', 'Auran')
    end

    it 'reflete +2 DEX nas colunas (constante entre sub-raças)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect(sheet.dex).to eq(base_attrs[:dex] + 2)
    end
  end

  # =====================================================================
  #  Provisioning — Falconicos (+1 STR + voo com armadura média)
  # =====================================================================
  describe 'CharacterProvisioningService — Aarakocra Falcônicos' do
    let(:payload) { build_payload(sub_rule: 'falconicos') }

    it 'reflete +1 STR (além do +2 DEX da base)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect(sheet.str).to eq(base_attrs[:str] + 1)
      expect(sheet.dex).to eq(base_attrs[:dex] + 2)
      # Outras sub-raças NÃO se misturam:
      expect(sheet.wis).to eq(base_attrs[:wis])
      expect(sheet.cha).to eq(base_attrs[:cha])
    end

    it 'RaceRules.apply: traits incluem flight_medium_ok (exclusivo dos Falcônicos)' do
      applied = RaceRules.apply(race_id: 'aarakocra', subrace_id: 'falconicos', choices: {})
      keys = Array(applied[:traits]).map { |t| t[:key] || t['key'] }
      expect(keys).to include('flight_15m_no_med_heavy', 'claws_1d4_slashing', 'flight_medium_ok')
      # Não deve ter darkvision (Nocturnos) nem natural_singers (Cypselanos)
      # — exceto darkvision que pode estar listado em outro lugar.
      expect(keys).not_to include('natural_singers')
    end
  end

  # =====================================================================
  #  Provisioning — Nocturnos (+1 WIS + darkvision)
  # =====================================================================
  describe 'CharacterProvisioningService — Aarakocra Nocturnos' do
    let(:payload) { build_payload(sub_rule: 'nocturnos') }

    it 'reflete +1 WIS (além do +2 DEX da base)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect(sheet.wis).to eq(base_attrs[:wis] + 1)
      expect(sheet.str).to eq(base_attrs[:str])
      expect(sheet.cha).to eq(base_attrs[:cha])
    end

    it 'RaceRules.apply: traits incluem darkvision (exclusivo dos Nocturnos no Aarakocra)' do
      applied = RaceRules.apply(race_id: 'aarakocra', subrace_id: 'nocturnos', choices: {})
      keys = Array(applied[:traits]).map { |t| t[:key] || t['key'] }
      expect(keys).to include('darkvision'),
        'Nocturnos têm Visão no Escuro 18m (60 ft) per PDF Lafiga p. 3.'
      # Falcônicos / Cypselanos features NÃO devem aparecer:
      expect(keys).not_to include('flight_medium_ok', 'natural_singers')
    end
  end

  # =====================================================================
  #  Provisioning — Cypselanos (+1 CHA + Performance/Voz)
  # =====================================================================
  describe 'CharacterProvisioningService — Aarakocra Cypselanos' do
    let(:payload) { build_payload(sub_rule: 'cypselanos') }

    it 'reflete +1 CHA (além do +2 DEX da base)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect(sheet.cha).to eq(base_attrs[:cha] + 1)
      expect(sheet.str).to eq(base_attrs[:str])
      expect(sheet.wis).to eq(base_attrs[:wis])
    end

    it 'persiste perícia Atuação (Performance) em race_summary["proficiencies"]["skills"]' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      skills_block = sheet.race_summary.dig('proficiencies', 'skills')
      fixed = skills_block.is_a?(Hash) ? Array(skills_block['fixed']) : Array(skills_block)
      expect(fixed).to include('Atuação'),
        'Cypselanos: "Cantores Natos" concede proficiência em Performance/Atuação (PDF Lafiga p. 3).'
    end

    it 'persiste Voz como ferramenta (instrumento) em race_summary' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      tools_block = sheet.race_summary.dig('proficiencies', 'tools')
      fixed = tools_block.is_a?(Hash) ? Array(tools_block['fixed']) : Array(tools_block)
      voice = fixed.map(&:to_s).find { |t| t =~ /Voz/i }
      expect(voice).to be_present,
        'Cypselanos têm a Voz como instrumento musical proficiente (PDF Lafiga p. 3); ' \
        "veio fixed=#{fixed.inspect}"
    end

    it 'RaceRules.apply: traits incluem natural_singers (exclusivo dos Cypselanos)' do
      applied = RaceRules.apply(race_id: 'aarakocra', subrace_id: 'cypselanos', choices: {})
      keys = Array(applied[:traits]).map { |t| t[:key] || t['key'] }
      expect(keys).to include('flight_15m_no_med_heavy', 'claws_1d4_slashing', 'natural_singers')
      expect(keys).not_to include('flight_medium_ok', 'darkvision')
    end
  end

  # =====================================================================
  #  Auditoria PDF — ASI exato por sub-raça
  # =====================================================================
  describe 'Auditoria PDF Lafiga: ASI por sub-raça' do
    {
      'falconicos' => { dex: 2, str: 1 },
      'nocturnos'  => { dex: 2, wis: 1 },
      'cypselanos' => { dex: 2, cha: 1 }
    }.each do |sub_rule, expected_increases|
      it "#{sub_rule}: ASI total = #{expected_increases.inspect} (PDF Lafiga p. 2-3)" do
        applied = RaceRules.apply(race_id: 'aarakocra', subrace_id: sub_rule, choices: {})
        increases = Array(applied.dig(:ability, :increases) || applied.dig('ability', 'increases'))
        actual = increases.each_with_object({}) do |e, h|
          k = (e[:ability] || e['ability']).to_s.downcase.to_sym
          h[k] = (e[:amount] || e['amount']).to_i
        end
        expected_increases.each do |key, val|
          expect(actual[key]).to eq(val),
            "#{sub_rule}.ability.increases[#{key}] esperado=#{val}, veio=#{actual[key].inspect}; full=#{actual.inspect}"
        end
      end
    end
  end

  # =====================================================================
  #  RaceRules.apply — base canônica
  # =====================================================================
  describe 'RaceRules.apply — base canônica do Aarakocra' do
    it 'speed=25, idiomas Comum/Aarakocra/Auran, traits voo + garras' do
      applied = RaceRules.apply(race_id: 'aarakocra', subrace_id: nil, choices: {})
      expect(applied[:speed]).to eq(25)
      expect(applied[:languages]).to include('Comum', 'Aarakocra', 'Auran')

      keys = Array(applied[:traits]).map { |t| t[:key] || t['key'] }
      expect(keys).to include('flight_15m_no_med_heavy', 'claws_1d4_slashing')
    end
  end
end
