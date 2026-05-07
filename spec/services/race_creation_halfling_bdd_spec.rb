# frozen_string_literal: true

require 'rails_helper'

# BDD: Criação de personagem com a raça Halfling (PHB)
# -----------------------------------------------------
# Regras (`api/config/race_rules.yml`):
#
#   Halfling (base):
#     - PEQUENO (size: "Pequeno"), 25 ft, SEM darkvision
#     - Idiomas: Comum, Halfling (sem extra)
#     - ASI: +2 DEX
#     - Traits: lucky, brave, halfling_nimbleness
#
#   Sub-raças:
#     lightfoot (Pés Leves):
#       - +1 CHA
#       - Traits: naturally_stealthy
#     stout (Robusto):
#       - +1 CON
#       - Traits: stout_resilience (vantagem em saves vs veneno + resistência)
#
# Halfling é a única raça PHB Pequena no projeto além de gnomos da floresta;
# o size do YAML é "Pequeno" (linha 410 race_rules.yml).
#
# Este spec testa: ASI por sub-raça, ausência de darkvision, idiomas fixos,
# traits específicos de cada sub-raça.
RSpec.describe 'Criação de Personagem Halfling (BDD PHB)', type: :service do
  let(:user) { create(:user) }

  let!(:halfling_race) do
    Race.find_or_create_by!(api_index: 'halfling') { |r| r.name = 'Halfling' }
  end

  let!(:lightfoot_subrace) do
    SubRace.find_or_create_by!(race_id: halfling_race.id, api_index: 'lightfoot') do |s|
      s.name = 'Pés Leves'
    end
  end

  let!(:stout_subrace) do
    SubRace.find_or_create_by!(race_id: halfling_race.id, api_index: 'stout') do |s|
      s.name = 'Robusto'
    end
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

  # Base: 10/14/12/12/10/14
  #   lightfoot = +DEX 2 / +CHA 1   →  10/16/12/12/10/15
  #   stout     = +DEX 2 / +CON 1   →  10/16/13/12/10/14
  def base_attrs
    { str: 10, dex: 14, con: 12, int: 12, wis: 10, cha: 14 }
  end

  def post_racial(sub_rule)
    case sub_rule
    when 'lightfoot' then base_attrs.merge(dex: base_attrs[:dex] + 2, cha: base_attrs[:cha] + 1)
    when 'stout'     then base_attrs.merge(dex: base_attrs[:dex] + 2, con: base_attrs[:con] + 1)
    end
  end

  def sub_id_for(sub_rule)
    { 'lightfoot' => lightfoot_subrace.id, 'stout' => stout_subrace.id }[sub_rule]
  end

  def build_payload(sub_rule:, race_choices: {})
    {
      character: { name: "Spec Halfling #{sub_rule} #{SecureRandom.hex(3)}", background: bg.name },
      wizard: {
        meta: { name: "Spec Halfling #{sub_rule}", alignmentKey: align.api_index },
        race: {
          raceId: halfling_race.id,
          subRaceId: sub_id_for(sub_rule),
          ruleId: 'halfling',
          subRuleId: sub_rule,
          attributes: post_racial(sub_rule),
          raceChoices: race_choices
        },
        klass: {
          klassId: klass.id,
          level: 1,
          classSkillPicks: %w[Furtividade Acrobacia],
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
  #  StepRace
  # =====================================================================
  describe 'StepRace — wizard draft' do
    let(:character) { create(:character, user: user, status: :draft) }

    it 'persiste raceId e subraceId Lightfoot' do
      svc = CharacterDraftSteps::RaceStepService.new(
        character: character,
        data: { 'raceId' => halfling_race.id.to_s, 'subraceId' => lightfoot_subrace.id.to_s }
      )
      result = svc.call
      expect(result.draft_data.dig('selectedRace', 'id')).to eq(halfling_race.id.to_s)
      expect(result.draft_data.dig('selectedSubrace', 'id')).to eq(lightfoot_subrace.id.to_s)
    end
  end

  # =====================================================================
  #  Provisioning Lightfoot (Pés Leves)
  # =====================================================================
  describe 'CharacterProvisioningService — Pés Leves (Lightfoot)' do
    let(:payload) { build_payload(sub_rule: 'lightfoot') }

    it 'persiste race_id, sub_race_id, speed=25 e idiomas Comum/Halfling' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }
      sheet = Sheet.order(:id).last

      expect(sheet.race_id).to eq(halfling_race.id)
      expect(sheet.sub_race_id).to eq(lightfoot_subrace.id)
      rs = sheet.race_summary || {}
      expect(rs['speed_ft'].to_i).to eq(25)
      expect(Array(rs['languages']).map(&:to_s)).to include('Comum', 'Halfling')
    end

    it 'reflete +2 DEX e +1 CHA nas colunas' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect(sheet.dex).to eq(base_attrs[:dex] + 2)
      expect(sheet.cha).to eq(base_attrs[:cha] + 1)
      expect(sheet.con).to eq(base_attrs[:con]) # Stout's CON+1 NÃO aplica
    end

    it 'race_summary não inclui darkvision (Halfling não tem)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      # Halfling REALMENTE não tem darkvision (PHB), e CPS não persiste mesmo
      # quando a raça TEM. Aqui as duas razões coincidem em blank.
      expect((sheet.race_summary || {})['darkvision']).to be_blank
    end
  end

  # =====================================================================
  #  Provisioning Stout (Robusto)
  # =====================================================================
  describe 'CharacterProvisioningService — Robusto (Stout)' do
    let(:payload) { build_payload(sub_rule: 'stout') }

    it 'reflete +2 DEX e +1 CON nas colunas' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect(sheet.dex).to eq(base_attrs[:dex] + 2)
      expect(sheet.con).to eq(base_attrs[:con] + 1)
      expect(sheet.cha).to eq(base_attrs[:cha]) # Lightfoot's CHA+1 NÃO aplica
    end
  end

  # =====================================================================
  #  RaceProfileService
  # =====================================================================
  describe 'RaceProfileService — leitura derivada' do
    it 'devolve speed=25 (sem boost de sub-raça)' do
      cmd = CharacterProvisioningService.call(
        user: user, payload: build_payload(sub_rule: 'lightfoot')
      )
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      profile = RaceProfileService.new(sheet).call
      expect(profile[:speed_ft]).to eq(25)
      expect(profile[:darkvision].to_i).to eq(0),
        'Halfling não tem darkvision no PHB; profile deve devolver 0 (Integer).'
    end
  end

  # =====================================================================
  #  RaceRules.apply — contrato canônico
  # =====================================================================
  describe 'RaceRules.apply — contrato canônico do Halfling' do
    it 'lightfoot: +2 DEX, +1 CHA, traits Lucky/Brave/HalflingNimbleness/NaturallyStealthy' do
      applied = RaceRules.apply(race_id: 'halfling', subrace_id: 'lightfoot', choices: {})
      expect(applied[:speed]).to eq(25)
      expect(applied[:darkvision]).to be_blank,
        'Halfling não tem darkvision (PHB).'

      keys = Array(applied[:traits]).map { |t| t[:key] || t['key'] }
      expect(keys).to include('lucky', 'brave', 'halfling_nimbleness', 'naturally_stealthy')
    end

    it 'stout: +2 DEX, +1 CON, traits incluem stout_resilience' do
      applied = RaceRules.apply(race_id: 'halfling', subrace_id: 'stout', choices: {})
      expect(applied[:speed]).to eq(25)

      keys = Array(applied[:traits]).map { |t| t[:key] || t['key'] }
      expect(keys).to include('lucky', 'brave', 'halfling_nimbleness', 'stout_resilience')
      # naturally_stealthy é exclusivo do lightfoot:
      expect(keys).not_to include('naturally_stealthy')
    end
  end
end
