# frozen_string_literal: true

require 'rails_helper'

# BDD: Criação de personagem com a raça Tabaxi
# ----------------------------------------------
# FONTE: Tabaxi vem de **Volo's Guide to Monsters** (WotC, oficial), não do
# PHB nem do PDF de houserules Lafiga (`Atualizacao_das_Racas.pdf`). Está no
# `api/config/race_rules.yml:442-463` como raça top-level (sem sub-raças)
# implementada conforme as regras do livro Volo's:
#
#   Tabaxi:
#     - Médio, 9 m (30 ft), darkvision 18 m (60 ft)
#     - Idiomas: Comum + 1 idioma à escolha (choiceCount: 1)
#     - ASI: +2 DEX, +1 CHA
#     - Perícias fixas: Percepção, Furtividade
#     - Traits: feline_agility (dobra speed 1x/turno até parar),
#       cat_claws_1d4_slashing (garras + escalada),
#       cats_talent (Percepção/Furtividade — redundante com fixed),
#       darkvision
#
# Sem sub-raças. Spec valida persistência via CPS + RaceRules.apply.
RSpec.describe 'Criação de Personagem Tabaxi (Volo\'s Guide)', type: :service do
  let(:user) { create(:user) }

  let!(:tabaxi_race) do
    Race.find_or_create_by!(api_index: 'tabaxi') { |r| r.name = 'Tabaxi' }
  end

  let!(:klass) do
    Klass.find_or_create_by!(api_index: 'rogue') do |k|
      k.name = 'Ladino'; k.hit_die = 8; k.subclass_level = 3
    end
  end

  let!(:bg) do
    Background.find_or_create_by!(api_index: 'criminal') do |b|
      b.name = 'Criminoso'; b.feature_name = 'Contato Criminoso'; b.feature_desc = 'Spec'
    end
  end

  let!(:align) do
    Alignment.find_or_create_by!(api_index: 'cn') { |a| a.name = 'Caótico e Neutro' }
  end

  # Base 10/14/12/10/12/13. Tabaxi = +2 DEX, +1 CHA → 10/16/12/10/12/14.
  def base_attrs
    { str: 10, dex: 14, con: 12, int: 10, wis: 12, cha: 13 }
  end

  def post_racial
    base_attrs.merge(dex: base_attrs[:dex] + 2, cha: base_attrs[:cha] + 1)
  end

  def build_payload(race_choices: { 'chosenLanguages' => ['Élfico'] })
    {
      character: { name: "Spec Tabaxi #{SecureRandom.hex(3)}", background: bg.name },
      wizard: {
        meta: { name: 'Spec Tabaxi', alignmentKey: align.api_index },
        race: {
          raceId: tabaxi_race.id,
          subRaceId: nil,
          ruleId: 'tabaxi',
          subRuleId: nil,
          attributes: post_racial,
          raceChoices: race_choices
        },
        klass: {
          klassId: klass.id,
          level: 1,
          classSkillPicks: %w[Acrobacia Investigação],
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
  #  Provisioning
  # =====================================================================
  describe 'CharacterProvisioningService — Tabaxi' do
    let(:payload) { build_payload }

    it 'persiste race_id, speed=30 e idiomas Comum + 1 extra escolhido' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }
      sheet = Sheet.order(:id).last

      expect(sheet.race_id).to eq(tabaxi_race.id)
      rs = sheet.race_summary || {}
      expect(rs['speed_ft'].to_i).to eq(30)
      langs = Array(rs['languages']).map(&:to_s)
      expect(langs).to include('Comum', 'Élfico')
    end

    it 'reflete +2 DEX e +1 CHA nas colunas (Volo\'s)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect(sheet.dex).to eq(base_attrs[:dex] + 2)
      expect(sheet.cha).to eq(base_attrs[:cha] + 1)
      expect(sheet.str).to eq(base_attrs[:str])
      expect(sheet.con).to eq(base_attrs[:con])
      expect(sheet.int).to eq(base_attrs[:int])
      expect(sheet.wis).to eq(base_attrs[:wis])
    end

    it 'persiste perícias fixas Percepção e Furtividade em race_summary' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      skills_block = sheet.race_summary.dig('proficiencies', 'skills')
      fixed = skills_block.is_a?(Hash) ? Array(skills_block['fixed']) : Array(skills_block)
      expect(fixed).to include('Percepção', 'Furtividade')
    end

    it 'CharacterSheetSummaryService inclui ambas em proficiencies.skills.race' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      summary = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
      expect(summary.success?).to be(true)
      race_skills = Array(summary.result.dig(:proficiencies, :skills, :race)).map(&:to_s)
      expect(race_skills).to include('Percepção', 'Furtividade')
    end

    it 'persiste raceChoices.chosenLanguages em metadata' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      rc = (sheet.metadata || {})['race_choices'] || {}
      expect(Array(rc['chosenLanguages'])).to include('Élfico')
    end
  end

  # =====================================================================
  #  RaceProfileService
  # =====================================================================
  describe 'RaceProfileService — leitura derivada' do
    it 'devolve speed=30 e idiomas com extra escolhido' do
      cmd = CharacterProvisioningService.call(user: user, payload: build_payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      profile = RaceProfileService.new(sheet).call
      expect(profile[:speed_ft]).to eq(30)
      expect(profile[:languages]).to include('Comum', 'Élfico')
    end
  end

  # =====================================================================
  #  RaceRules.apply — contrato canônico
  # =====================================================================
  describe 'RaceRules.apply — contrato canônico do Tabaxi' do
    it 'speed=30, darkvision=60, ASI DEX+2/CHA+1, Percepção+Furtividade fixas' do
      applied = RaceRules.apply(race_id: 'tabaxi', subrace_id: nil, choices: { extraLanguages: ['Halfling'] })
      expect(applied[:speed]).to eq(30)
      dv = applied[:darkvision]
      val = dv.is_a?(Hash) ? (dv[:range] || dv['range']) : dv
      expect(val.to_i).to eq(60)
      expect(applied[:languages]).to include('Comum', 'Halfling')

      ability = applied[:ability] || {}
      increases = ability[:increases] || ability['increases'] || []
      pairs = increases.map { |e| [(e[:ability] || e['ability']).to_s, (e[:amount] || e['amount']).to_i] }
      expect(pairs).to include(['DEX', 2], ['CHA', 1])

      skills = applied.dig(:proficiencies, :skills) || applied.dig('proficiencies', 'skills') || {}
      fixed = skills[:fixed] || skills['fixed'] || []
      expect(Array(fixed)).to include('Percepção', 'Furtividade')
    end

    it 'traits incluem darkvision, feline_agility, cat_claws_1d4_slashing, cats_talent' do
      applied = RaceRules.apply(race_id: 'tabaxi', subrace_id: nil, choices: {})
      keys = Array(applied[:traits]).map { |t| t[:key] || t['key'] }
      expect(keys).to include('darkvision', 'feline_agility', 'cat_claws_1d4_slashing', 'cats_talent')
    end
  end

  # =====================================================================
  #  GAPs do sistema
  # =====================================================================
  describe 'CPS persiste darkvision em race_summary' do
    it 'darkvision=60 para Tabaxi' do
      cmd = CharacterProvisioningService.call(user: user, payload: build_payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect((sheet.race_summary || {})['darkvision'].to_i).to eq(60)
    end
  end
end
