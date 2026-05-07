# frozen_string_literal: true

require 'rails_helper'

# BDD: Criação de personagem com a raça Meio-Orc (Half-Orc, PHB)
# ---------------------------------------------------------------
# AUDITORIA PHB↔YAML (livro_do_jogador.txt linhas 2038-2200) confirma:
#   - Tamanho: Médio
#   - Deslocamento: 9 m (30 ft)
#   - Visão no Escuro: 18 m (60 ft)  → trait darkvision
#   - Idiomas: Comum, Orc (sem extra à escolha)
#   - ASI: +2 Força, +1 Constituição
#   - Ameaçador: proficiência em Intimidação (fixa)
#   - Resistência Implacável: ao cair a 0 PV, volta para 1 (1x/descanso longo)
#   - Ataques Selvagens: 1 dado extra de dano em crítico corpo-a-corpo
#
# YAML (`api/config/race_rules.yml:385-404`):
#   - speed: 30, darkvision: 60, langs always [Comum, Orc], choiceCount 0
#   - ASI: STR+2, CON+1 (type: fixed)
#   - skills.fixed: [Intimidação]
#   - traits: relentless_endurance, savage_attacks, darkvision
#
# Sem sub-raças. Spec valida persistência via CPS + RaceRules.apply.
RSpec.describe 'Criação de Personagem Meio-Orc (BDD PHB)', type: :service do
  let(:user) { create(:user) }

  let!(:half_orc_race) do
    Race.find_or_create_by!(api_index: 'half_orc') { |r| r.name = 'Meio-Orc' }
  end

  let!(:klass) do
    Klass.find_or_create_by!(api_index: 'barbarian') do |k|
      k.name = 'Bárbaro'; k.hit_die = 12; k.subclass_level = 3
    end
  end

  let!(:bg) do
    Background.find_or_create_by!(api_index: 'outlander') do |b|
      b.name = 'Forasteiro'; b.feature_name = 'Errante'; b.feature_desc = 'Spec'
    end
  end

  let!(:align) do
    Alignment.find_or_create_by!(api_index: 'cn') { |a| a.name = 'Caótico e Neutro' }
  end

  # Base 13/12/13/8/10/10. Meio-Orc = +STR 2, +CON 1 → 15/12/14/8/10/10.
  def base_attrs
    { str: 13, dex: 12, con: 13, int: 8, wis: 10, cha: 10 }
  end

  def post_racial
    base_attrs.merge(str: base_attrs[:str] + 2, con: base_attrs[:con] + 1)
  end

  def build_payload
    {
      character: { name: "Spec HalfOrc #{SecureRandom.hex(3)}", background: bg.name },
      wizard: {
        meta: { name: 'Spec HalfOrc', alignmentKey: align.api_index },
        race: {
          raceId: half_orc_race.id,
          subRaceId: nil,
          ruleId: 'half_orc',
          subRuleId: nil,
          attributes: post_racial,
          raceChoices: {}
        },
        klass: {
          klassId: klass.id,
          level: 1,
          classSkillPicks: %w[Atletismo Sobrevivência],
          classPicksByLevel: { '1' => { 'hp' => { 'dieResult' => 12, 'total' => 14, 'method' => 'average' } } }
        },
        background: { backgroundName: bg.name, backgroundKey: bg.api_index },
        equipment: {},
        avatar: { customization: {} }
      }
    }
  end

  before { RaceRules.reload! }

  # =====================================================================
  #  Provisioning
  # =====================================================================
  describe 'CharacterProvisioningService — Meio-Orc' do
    let(:payload) { build_payload }

    it 'persiste race_id, speed=30 e idiomas Comum/Orc (sem extra)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }
      sheet = Sheet.order(:id).last

      expect(sheet.race_id).to eq(half_orc_race.id)
      rs = sheet.race_summary || {}
      expect(rs['speed_ft'].to_i).to eq(30)
      langs = Array(rs['languages']).map(&:to_s)
      expect(langs).to include('Comum', 'Orc')
      # choiceCount: 0 ⇒ apenas os 2 idiomas always.
      expect(langs.size).to eq(2)
    end

    it 'reflete +2 STR e +1 CON nas colunas (sem +CHA, +DEX, etc.)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      expect(sheet.str).to eq(base_attrs[:str] + 2),
        "Meio-Orc: +2 STR fixo (PHB); coluna deve ser #{base_attrs[:str] + 2}"
      expect(sheet.con).to eq(base_attrs[:con] + 1),
        "Meio-Orc: +1 CON fixo (PHB); coluna deve ser #{base_attrs[:con] + 1}"
      expect(sheet.dex).to eq(base_attrs[:dex])
      expect(sheet.int).to eq(base_attrs[:int])
      expect(sheet.wis).to eq(base_attrs[:wis])
      expect(sheet.cha).to eq(base_attrs[:cha])
    end

    it 'persiste perícia Intimidação (Ameaçador) em race_summary["proficiencies"]["skills"]' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      skills_block = sheet.race_summary.dig('proficiencies', 'skills')
      fixed = skills_block.is_a?(Hash) ? Array(skills_block['fixed']) : Array(skills_block)
      expect(fixed).to include('Intimidação'),
        '"Ameaçador" do PHB: proficiência fixa em Intimidação.'
    end

    it 'CharacterSheetSummaryService inclui Intimidação em proficiencies.skills.race' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      summary = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
      expect(summary.success?).to be(true)
      race_skills = Array(summary.result.dig(:proficiencies, :skills, :race)).map(&:to_s)
      expect(race_skills).to include('Intimidação')
    end
  end

  # =====================================================================
  #  RaceProfileService
  # =====================================================================
  describe 'RaceProfileService — leitura derivada' do
    it 'devolve speed=30 e idiomas Comum/Orc' do
      cmd = CharacterProvisioningService.call(user: user, payload: build_payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      profile = RaceProfileService.new(sheet).call
      expect(profile[:speed_ft]).to eq(30)
      expect(profile[:languages]).to include('Comum', 'Orc')
    end
  end

  # =====================================================================
  #  RaceRules.apply — contrato canônico
  # =====================================================================
  describe 'RaceRules.apply — contrato canônico do Meio-Orc' do
    it 'speed 30, darkvision 60, ASI STR+2/CON+1, Intimidação fixa' do
      applied = RaceRules.apply(race_id: 'half_orc', subrace_id: nil, choices: {})
      expect(applied[:speed]).to eq(30)
      dv = applied[:darkvision]
      val = dv.is_a?(Hash) ? (dv[:range] || dv['range']) : dv
      expect(val.to_i).to eq(60)
      expect(applied[:languages]).to include('Comum', 'Orc')

      ability = applied[:ability] || {}
      increases = ability[:increases] || ability['increases'] || []
      pairs = increases.map { |e| [(e[:ability] || e['ability']).to_s, (e[:amount] || e['amount']).to_i] }
      expect(pairs).to include(['STR', 2], ['CON', 1])

      skills = applied.dig(:proficiencies, :skills) || applied.dig('proficiencies', 'skills') || {}
      fixed = skills[:fixed] || skills['fixed'] || []
      expect(Array(fixed)).to include('Intimidação')
    end

    it 'traits incluem relentless_endurance, savage_attacks, darkvision' do
      applied = RaceRules.apply(race_id: 'half_orc', subrace_id: nil, choices: {})
      keys = Array(applied[:traits]).map { |t| t[:key] || t['key'] }
      expect(keys).to include('relentless_endurance', 'savage_attacks', 'darkvision')
    end
  end

  # =====================================================================
  #  GAPs
  # =====================================================================
  describe 'CPS persiste darkvision em race_summary' do
    it 'darkvision=60 para Meio-Orc' do
      cmd = CharacterProvisioningService.call(user: user, payload: build_payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect((sheet.race_summary || {})['darkvision'].to_i).to eq(60)
    end
  end
end
