# frozen_string_literal: true

require 'rails_helper'

# BDD: Criação de personagem com a raça Elfo (Elf, PHB)
# ------------------------------------------------------
# Regras (`api/config/race_rules.yml`):
#
#   Elfo (base):
#     - Médio, 30 ft, darkvision 60
#     - Idiomas: Comum, Élfico (sem extra à escolha na base)
#     - ASI: +2 DEX
#     - Perícia: Percepção (fixa)
#     - Traits: fey_ancestry, trance, keen_senses, darkvision
#
#   Sub-raças:
#     high (Alto Elfo):
#       - +1 INT
#       - Weapons: espada longa, espada curta, arco curto, arco longo
#       - +1 idioma extra à escolha (choiceCount: 1 com choiceList do PHB)
#       - 1 cantrip de mago à escolha (trait `high_elf_cantrip`, INT)
#     wood (Elfo da Floresta):
#       - +1 WIS
#       - 35 ft de deslocamento (Fleet of Foot — sub-raça SOBRESCREVE 30→35)
#       - Mesmas armas do High
#       - Traits: fleet_of_foot, mask_of_the_wild
#     drow (Elfo Negro):
#       - +1 CHA
#       - Weapons: rapieira, espada curta, besta de mão
#       - Superior darkvision (120 ft) + sunlight_sensitivity
#       - Drow magic (innate spells: dancing-lights/faerie-fire/darkness)
#
# Coberturas pré-existentes que este arquivo COMPLEMENTA:
#   - race_profile_service_spec.rb: Wood Elf 35 ft + Drow 30 ft (speed only)
#   - character_provisioning_service_race_summary_spec.rb: Wood Elf full
#     payload + perícia Percepção em race_summary["proficiencies"]["skills"]
#   - racial_spells_service_spec.rb: Drow innate spells (cantrip/level 1/etc)
#
# Foco deste arquivo: ASI por sub-raça (DEX+INT, DEX+WIS, DEX+CHA), weapons
# canônicas por sub-raça, idioma extra do High, traits específicos (fey_ancestry
# universal + fleet_of_foot/mask_of_the_wild Wood + sunlight_sensitivity Drow).
#
# Bugs do sistema documentados como `pending` (mesmos do spec do Anão):
#   - CPS não persiste darkvision em race_summary (gap de simetria com RaceEditService)
RSpec.describe 'Criação de Personagem Elfo (BDD PHB)', type: :service do
  let(:user) { create(:user) }

  let!(:elf_race) do
    Race.find_or_create_by!(api_index: 'elf') { |r| r.name = 'Elfo' }
  end

  let!(:high_subrace) do
    SubRace.find_or_create_by!(race_id: elf_race.id, api_index: 'high') do |s|
      s.name = 'Alto Elfo'
    end
  end

  let!(:wood_subrace) do
    SubRace.find_or_create_by!(race_id: elf_race.id, api_index: 'wood') do |s|
      s.name = 'Elfo da Floresta'
    end
  end

  let!(:drow_subrace) do
    SubRace.find_or_create_by!(race_id: elf_race.id, api_index: 'drow') do |s|
      s.name = 'Elfo Negro (Drow)'
    end
  end

  let!(:klass) do
    Klass.find_or_create_by!(api_index: 'fighter') do |k|
      k.name = 'Guerreiro'; k.hit_die = 10; k.subclass_level = 3
    end
  end

  let!(:bg) do
    Background.find_or_create_by!(api_index: 'soldier') do |b|
      b.name = 'Soldado'; b.feature_name = 'Patente Militar'; b.feature_desc = 'Spec'
    end
  end

  let!(:align) do
    Alignment.find_or_create_by!(api_index: 'lg') { |a| a.name = 'Leal e Bom' }
  end

  # Base: 13/14/13/10/12/8.
  #   High     = +DEX 2 / +INT 1   →  13/16/13/11/12/8
  #   Wood     = +DEX 2 / +WIS 1   →  13/16/13/10/13/8
  #   Drow     = +DEX 2 / +CHA 1   →  13/16/13/10/12/9
  def base_attrs
    { str: 13, dex: 14, con: 13, int: 10, wis: 12, cha: 8 }
  end

  def post_racial(sub_rule)
    case sub_rule
    when 'high'  then base_attrs.merge(dex: base_attrs[:dex] + 2, int: base_attrs[:int] + 1)
    when 'wood'  then base_attrs.merge(dex: base_attrs[:dex] + 2, wis: base_attrs[:wis] + 1)
    when 'drow'  then base_attrs.merge(dex: base_attrs[:dex] + 2, cha: base_attrs[:cha] + 1)
    else base_attrs
    end
  end

  def sub_id_for(sub_rule)
    { 'high' => high_subrace.id, 'wood' => wood_subrace.id, 'drow' => drow_subrace.id }[sub_rule]
  end

  def build_payload(sub_rule:, race_choices: {})
    {
      character: { name: "Spec Elf #{sub_rule} #{SecureRandom.hex(3)}", background: bg.name },
      wizard: {
        meta: { name: "Spec Elf #{sub_rule}", alignmentKey: align.api_index },
        race: {
          raceId: elf_race.id,
          subRaceId: sub_id_for(sub_rule),
          ruleId: 'elf',
          subRuleId: sub_rule,
          attributes: post_racial(sub_rule),
          raceChoices: race_choices
        },
        klass: {
          klassId: klass.id,
          level: 1,
          classSkillPicks: %w[Atletismo Intimidação],
          classPicksByLevel: { '1' => { 'hp' => { 'dieResult' => 10, 'total' => 12, 'method' => 'average' } } }
        },
        background: { backgroundName: bg.name, backgroundKey: bg.api_index },
        equipment: {},
        avatar: { customization: {} }
      }
    }
  end

  before { RaceRules.reload! }

  # =====================================================================
  #  StepRace — draft do wizard
  # =====================================================================
  describe 'StepRace — wizard draft' do
    let(:character) { create(:character, user: user, status: :draft) }

    it 'persiste raceId/subraceId/raceChoices para Alto Elfo (idioma extra esperado)' do
      svc = CharacterDraftSteps::RaceStepService.new(
        character: character,
        data: {
          'raceId' => elf_race.id.to_s,
          'subraceId' => high_subrace.id.to_s,
          'raceChoices' => { 'chosenLanguages' => ['Anão'] }
        }
      )
      result = svc.call

      expect(result.draft_data.dig('selectedRace', 'id')).to eq(elf_race.id.to_s)
      expect(result.draft_data.dig('selectedSubrace', 'id')).to eq(high_subrace.id.to_s)
      expect(result.draft_data.dig('raceChoices', 'chosenLanguages')).to eq(['Anão'])
    end

    it 'troca de subraça (Wood → Drow) preserva raceChoices da mesma chamada' do
      character.update!(draft_data: {
        '_raceId' => elf_race.id.to_s,
        'selectedRace' => { 'id' => elf_race.id.to_s },
        'selectedSubrace' => { 'id' => wood_subrace.id.to_s },
        'raceChoices' => {}
      })
      svc = CharacterDraftSteps::RaceStepService.new(
        character: character,
        data: { 'subraceId' => drow_subrace.id.to_s, 'raceChoices' => {} }
      )
      result = svc.call

      expect(result.draft_data.dig('selectedSubrace', 'id')).to eq(drow_subrace.id.to_s)
    end
  end

  # =====================================================================
  #  Provisioning — Elfo base (validamos via High que herda tudo)
  # =====================================================================
  describe 'CharacterProvisioningService — Elfo base (verifica via High)' do
    let(:payload) do
      build_payload(sub_rule: 'high', race_choices: { 'chosenLanguages' => ['Anão'] })
    end

    it 'persiste race_id, sub_race_id e race_summary speed=30' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }
      sheet = Sheet.order(:id).last

      expect(sheet.race_id).to eq(elf_race.id)
      expect(sheet.sub_race_id).to eq(high_subrace.id)
      expect((sheet.race_summary || {})['speed_ft'].to_i).to eq(30)
    end

    it 'inclui Comum + Élfico em race_summary["languages"]' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      langs = Array((sheet.race_summary || {})['languages']).map(&:to_s)
      expect(langs).to include('Comum', 'Élfico')
    end

    it 'persiste perícia Percepção (fixa do Elfo) em race_summary["proficiencies"]["skills"]' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      skills_block = sheet.race_summary.dig('proficiencies', 'skills')
      fixed = skills_block.is_a?(Hash) ? Array(skills_block['fixed']) : Array(skills_block)
      expect(fixed).to include('Percepção')
    end

    it 'CharacterSheetSummaryService inclui Percepção em proficiencies.skills.race' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      summary = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
      expect(summary.success?).to be(true)
      race_skills = Array(summary.result.dig(:proficiencies, :skills, :race)).map(&:to_s)
      expect(race_skills).to include('Percepção')
    end
  end

  # =====================================================================
  #  Provisioning — Alto Elfo (High)
  # =====================================================================
  describe 'CharacterProvisioningService — Alto Elfo (High)' do
    let(:payload) do
      build_payload(sub_rule: 'high', race_choices: { 'chosenLanguages' => ['Dracônico'] })
    end

    it 'reflete +2 DEX e +1 INT nas colunas' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      expect(sheet.dex).to eq(base_attrs[:dex] + 2)
      expect(sheet.int).to eq(base_attrs[:int] + 1)
      # Drow CHA / Wood WIS não devem aparecer aqui.
      expect(sheet.cha).to eq(base_attrs[:cha])
      expect(sheet.wis).to eq(base_attrs[:wis])
    end

    it 'inclui as 4 armas do treino élfico em race_summary' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      weapons = Array(sheet.race_summary.dig('proficiencies', 'weapons')).map { |w| w.to_s.downcase }
      %w[espada\ longa espada\ curta arco\ curto arco\ longo].each do |w|
        expect(weapons).to include(w)
      end
    end

    it 'inclui o idioma extra escolhido em race_summary["languages"]' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      langs = Array((sheet.race_summary || {})['languages']).map(&:to_s)
      expect(langs).to include('Comum', 'Élfico', 'Dracônico')
    end
  end

  # =====================================================================
  #  Provisioning — Elfo da Floresta (Wood)
  # =====================================================================
  describe 'CharacterProvisioningService — Elfo da Floresta (Wood)' do
    let(:payload) { build_payload(sub_rule: 'wood') }

    it 'reflete +2 DEX e +1 WIS nas colunas' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      expect(sheet.dex).to eq(base_attrs[:dex] + 2)
      expect(sheet.wis).to eq(base_attrs[:wis] + 1)
      # +1 INT (high) não aparece aqui.
      expect(sheet.int).to eq(base_attrs[:int])
    end

    it 'aplica deslocamento 35 ft (Fleet of Foot — sub-raça sobrescreve speed base)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect((sheet.race_summary || {})['speed_ft'].to_i).to eq(35)
    end

    it 'RaceProfileService devolve speed_ft=35 e speed_m derivado (~10.7)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      profile = RaceProfileService.new(sheet).call
      expect(profile[:speed_ft]).to eq(35)
      expect(profile[:speed_m]).to be_within(0.5).of(10.7)
    end
  end

  # =====================================================================
  #  Provisioning — Drow (Elfo Negro)
  # =====================================================================
  describe 'CharacterProvisioningService — Drow' do
    let(:payload) { build_payload(sub_rule: 'drow') }

    it 'reflete +2 DEX e +1 CHA nas colunas' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      expect(sheet.dex).to eq(base_attrs[:dex] + 2)
      expect(sheet.cha).to eq(base_attrs[:cha] + 1)
      # Speed NÃO muda para Drow (continua 30 ft, não Fleet of Foot).
      expect((sheet.race_summary || {})['speed_ft'].to_i).to eq(30)
    end

    it 'inclui as armas drow (rapieira, espada curta, besta de mão) em race_summary' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      weapons = Array(sheet.race_summary.dig('proficiencies', 'weapons')).map { |w| w.to_s.downcase }
      expect(weapons).to include('rapieira', 'espada curta', 'besta de mão')
    end
  end

  # =====================================================================
  #  Darkvision persistido em race_summary (CPS normaliza Hash {range:N})
  # =====================================================================
  describe 'CPS persiste darkvision em race_summary' do
    it 'darkvision=60 para Alto Elfo (PHB)' do
      cmd = CharacterProvisioningService.call(user: user, payload: build_payload(sub_rule: 'high'))
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect((sheet.race_summary || {})['darkvision'].to_i).to eq(60)
    end

    it 'darkvision=120 (Visão no Escuro Superior) em race_summary do Drow' do
      cmd = CharacterProvisioningService.call(user: user, payload: build_payload(sub_rule: 'drow'))
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      # Drow no YAML define `darkvision: { range: 120 }` na sub-raça, que via
      # deep_merge sobrescreve os 60 ft do elfo base. Antes do fix, a sub-raça
      # tinha apenas o trait `superior_darkvision range: 120` (sem o campo
      # `darkvision:` top-level), então `applied[:darkvision]` continuava 60.
      expect((sheet.race_summary || {})['darkvision'].to_i).to eq(120),
        'PHB: Drow tem Visão no Escuro Superior (120 ft / 36 m).'
    end
  end

  # =====================================================================
  #  RaceRules.apply — contrato canônico do YAML por sub-raça
  # =====================================================================
  describe 'RaceRules.apply — contrato canônico do Elfo' do
    it 'high: +2 DEX, +1 INT, +1 idioma extra, traits incluem high_elf_cantrip' do
      applied = RaceRules.apply(
        race_id: 'elf', subrace_id: 'high', choices: { extraLanguages: ['Anão'] }
      )
      expect(applied[:speed]).to eq(30)
      expect(applied[:languages]).to include('Comum', 'Élfico', 'Anão')

      keys = Array(applied[:traits]).map { |t| t[:key] || t['key'] }
      expect(keys).to include('fey_ancestry', 'trance', 'keen_senses', 'high_elf_cantrip')
    end

    it 'wood: speed 35, traits incluem fleet_of_foot e mask_of_the_wild' do
      applied = RaceRules.apply(race_id: 'elf', subrace_id: 'wood', choices: {})
      expect(applied[:speed]).to eq(35)

      keys = Array(applied[:traits]).map { |t| t[:key] || t['key'] }
      expect(keys).to include('fleet_of_foot', 'mask_of_the_wild')
    end

    it 'drow: traits incluem superior_darkvision, sunlight_sensitivity, drow_magic' do
      applied = RaceRules.apply(race_id: 'elf', subrace_id: 'drow', choices: {})
      expect(applied[:speed]).to eq(30)

      keys = Array(applied[:traits]).map { |t| t[:key] || t['key'] }
      expect(keys).to include('superior_darkvision', 'sunlight_sensitivity', 'drow_magic')
    end

    it 'drow: innate_spells inclui dancing-lights (cantrip)' do
      applied = RaceRules.apply(race_id: 'elf', subrace_id: 'drow', choices: {})
      spells = Array(applied[:innate_spells]).map { |s| (s[:name] || s['name']).to_s }
      # `drow_magic` em trait_definitions concede dancing-lights, faerie-fire, darkness.
      expect(spells).to include('dancing-lights').or include('Luz Dançante').or include('Luzes Dançantes')
    end
  end
end
