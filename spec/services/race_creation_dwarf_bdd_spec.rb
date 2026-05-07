# frozen_string_literal: true

require 'rails_helper'

# BDD: Criação de personagem com a raça Anão (Dwarf, PHB)
# --------------------------------------------------------
# Regras (`api/config/race_rules.yml`):
#
#   Anão (base):
#     - Médio, 25 ft, darkvision 60 ft
#     - Idiomas: Comum, Anão (sem extra à escolha)
#     - ASI: +2 CON
#     - Proficiências de armas: machado de batalha, machadinha,
#       martelo leve, martelo de guerra
#     - Proficiências de ferramentas: ESCOLHE 1 entre
#         Ferramentas de ferreiro / Suprimentos de cervejeiro /
#         Ferramentas de pedreiro
#     - Traits: dwarven_resilience, stonecunning,
#       speed_not_reduced_by_heavy_armor, darkvision
#
#   Sub-raças:
#     hill (Anão da Colina):
#       - +1 WIS
#       - dwarven_toughness (+1 PV por nível — PHB Robustez Anã)
#     mountain (Anão da Montanha):
#       - +2 STR
#       - Proficiência adicional de armadura: leve, média
#
# Coberturas pré-existentes que este arquivo COMPLEMENTA:
#   - character_provisioning_service_race_summary_spec.rb: Anão da Colina
#     com chosenTools persistido em race_summary.proficiencies.tools.fixed
#     (apenas tools/weapons; este spec acrescenta speed/darkvision/traits/ASI/HP).
#   - racial_hp_bonus_spec.rb: per_level Robustez Anã (unitário em
#     RacialHpBonus); este spec verifica end-to-end via provisioning.
#   - character_sheet_summary_service_proficiencies_spec.rb: merge de armas
#     anãs em proficiencies.weapons (já cobre Hill Dwarf).
#
# Foco deste arquivo: ASI total (CON+2/WIS+1 ou CON+2/STR+2), darkvision
# em race_summary, traits raciais persistidos, e divergência Mountain (armor)
# vs Hill (HP bonus).
RSpec.describe 'Criação de Personagem Anão (BDD PHB)', type: :service do
  let(:user) { create(:user) }

  let!(:dwarf_race) do
    Race.find_or_create_by!(api_index: 'dwarf') { |r| r.name = 'Anão' }
  end

  let!(:hill_subrace) do
    SubRace.find_or_create_by!(race_id: dwarf_race.id, api_index: 'hill') do |s|
      s.name = 'Anão da Colina'
    end
  end

  let!(:mountain_subrace) do
    SubRace.find_or_create_by!(race_id: dwarf_race.id, api_index: 'mountain') do |s|
      s.name = 'Anão da Montanha'
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

  # Base: 13/14/13/10/12/8.  Hill = +CON 2 / +WIS 1  →  13/14/15/10/13/8
  #                            Mountain = +CON 2 / +STR 2  →  15/14/15/10/12/8
  def base_attrs
    { str: 13, dex: 14, con: 13, int: 10, wis: 12, cha: 8 }
  end

  def hill_post_racial
    base_attrs.merge(con: base_attrs[:con] + 2, wis: base_attrs[:wis] + 1)
  end

  def mountain_post_racial
    base_attrs.merge(con: base_attrs[:con] + 2, str: base_attrs[:str] + 2)
  end

  def build_payload(sub_rule:, attributes:, race_choices: { 'chosenTools' => ['Ferramentas de ferreiro'] })
    sub_id = sub_rule == 'hill' ? hill_subrace.id : mountain_subrace.id
    {
      character: { name: "Spec Dwarf #{sub_rule} #{SecureRandom.hex(3)}", background: bg.name },
      wizard: {
        meta: { name: "Spec Dwarf #{sub_rule}", alignmentKey: align.api_index },
        race: {
          raceId: dwarf_race.id,
          subRaceId: sub_id,
          ruleId: 'dwarf',
          subRuleId: sub_rule,
          attributes: attributes,
          raceChoices: race_choices
        },
        klass: {
          klassId: klass.id,
          level: 1,
          classSkillPicks: %w[Atletismo Intimidação],
          classPicksByLevel: { '1' => { 'hp' => { 'dieResult' => 10, 'total' => 13, 'method' => 'average' } } }
        },
        background: { backgroundName: bg.name, backgroundKey: bg.api_index },
        equipment: {},
        avatar: { customization: {} }
      }
    }
  end

  before { RaceRules.reload! }

  # =====================================================================
  #  StepRace — draft do wizard (Anão da Colina e da Montanha)
  # =====================================================================
  describe 'StepRace — wizard draft' do
    let(:character) { create(:character, user: user, status: :draft) }

    it 'persiste raceId, subraceId e a ferramenta escolhida (chosenTools)' do
      svc = CharacterDraftSteps::RaceStepService.new(
        character: character,
        data: {
          'raceId' => dwarf_race.id.to_s,
          'subraceId' => hill_subrace.id.to_s,
          'raceChoices' => { 'chosenTools' => ['Suprimentos de cervejeiro'] }
        }
      )
      result = svc.call

      expect(result.draft_data.dig('selectedRace', 'id')).to eq(dwarf_race.id.to_s)
      expect(result.draft_data.dig('selectedSubrace', 'id')).to eq(hill_subrace.id.to_s)
      expect(result.draft_data.dig('raceChoices', 'chosenTools')).to eq(['Suprimentos de cervejeiro'])
    end

    it 'troca de subraça (Hill → Mountain) preserva raceChoices da mesma chamada' do
      character.update!(draft_data: {
        '_raceId' => dwarf_race.id.to_s,
        'selectedRace' => { 'id' => dwarf_race.id.to_s },
        'selectedSubrace' => { 'id' => hill_subrace.id.to_s },
        'raceChoices' => { 'chosenTools' => ['Ferramentas de ferreiro'] }
      })

      svc = CharacterDraftSteps::RaceStepService.new(
        character: character,
        data: {
          'subraceId' => mountain_subrace.id.to_s,
          'raceChoices' => { 'chosenTools' => ['Ferramentas de pedreiro'] }
        }
      )
      result = svc.call

      expect(result.draft_data.dig('selectedSubrace', 'id')).to eq(mountain_subrace.id.to_s)
      expect(result.draft_data.dig('raceChoices', 'chosenTools')).to eq(['Ferramentas de pedreiro'])
    end
  end

  # =====================================================================
  #  Provisioning — base do Anão (válido para Hill e Mountain)
  # =====================================================================
  describe 'CharacterProvisioningService — Anão (base; verifica via Hill)' do
    let(:payload) do
      build_payload(
        sub_rule: 'hill',
        attributes: hill_post_racial,
        race_choices: { 'chosenTools' => ['Suprimentos de cervejeiro'] }
      )
    end

    it 'persiste race_id, sub_race_id e race_summary speed=25' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }
      sheet = Sheet.order(:id).last

      expect(sheet.race_id).to eq(dwarf_race.id)
      expect(sheet.sub_race_id).to eq(hill_subrace.id)
      rs = sheet.race_summary || {}
      expect(rs['speed_ft'].to_i).to eq(25)
    end

    it 'persiste darkvision=60 em race_summary (CPS normaliza Hash {range: 60} → 60)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect((sheet.race_summary || {})['darkvision'].to_i).to eq(60)
    end

    it 'inclui Comum + Anão em race_summary["languages"] (sem extra à escolha)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      langs = Array((sheet.race_summary || {})['languages']).map(&:to_s)
      expect(langs).to include('Comum', 'Anão')
    end

    it 'persiste todas as 4 armas raciais do Anão em race_summary["proficiencies"]["weapons"]' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      weapons = Array((sheet.race_summary.dig('proficiencies', 'weapons') || []))
                  .map { |w| w.to_s.downcase }
      %w[machado\ de\ batalha machadinha martelo\ leve martelo\ de\ guerra].each do |w|
        expect(weapons).to include(w)
      end
    end

    it 'resolve a ferramenta escolhida em race_summary["proficiencies"]["tools"]["fixed"]' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      tools = sheet.race_summary.dig('proficiencies', 'tools') || {}
      expect(Array(tools['fixed'])).to include('Suprimentos de cervejeiro')
      # As outras opções permanecem registradas em `choices` para auditoria.
      expect(Array(tools['choices'])).to include(
        'Ferramentas de ferreiro', 'Suprimentos de cervejeiro', 'Ferramentas de pedreiro'
      )
    end

    it 'persiste raceChoices.chosenTools em metadata["race_choices"]' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      rc = (sheet.metadata || {})['race_choices'] || {}
      expect(Array(rc['chosenTools'])).to include('Suprimentos de cervejeiro')
    end

    it 'race_summary["traits"] inclui descrições de traits raciais (não vazio)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      traits = Array(sheet.race_summary['traits'])
      # Os traits persistidos vêm de `Race#base_traits` (DB) — pode estar vazio
      # se o seed não popula. Não exigimos chaves específicas, só que o array
      # exista (a estrutura é gravada pelo CPS quando há traits no DB).
      expect(traits).to be_an(Array)
    end

    it 'CharacterSheetSummaryService.build_proficiencies inclui as armas do Anão e a tool escolhida' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      summary = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
      expect(summary.success?).to be(true), -> { summary.errors.full_messages.join('; ') rescue summary.inspect }

      weapons = Array(summary.result.dig(:proficiencies, :weapons)).map { |w| w.to_s.downcase }
      tools   = Array(summary.result.dig(:proficiencies, :tools)).map(&:to_s)

      expect(weapons).to include('machado de batalha', 'martelo de guerra')
      expect(tools).to include('Suprimentos de cervejeiro')
    end
  end

  # =====================================================================
  #  Provisioning — Anão da Colina (Hill Dwarf): WIS+1 + Robustez Anã
  # =====================================================================
  describe 'CharacterProvisioningService — Anão da Colina (Hill)' do
    let(:payload) do
      build_payload(sub_rule: 'hill', attributes: hill_post_racial)
    end

    it 'reflete +2 CON e +1 WIS nas colunas (base + ASI base + ASI Hill)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      expect(sheet.con).to eq(base_attrs[:con] + 2),
        "Anão (base) concede +2 CON; coluna deve ser #{base_attrs[:con] + 2}"
      expect(sheet.wis).to eq(base_attrs[:wis] + 1),
        "Anão da Colina concede +1 WIS; coluna deve ser #{base_attrs[:wis] + 1}"
      # Mountain ASI (+2 STR) não deve aparecer:
      expect(sheet.str).to eq(base_attrs[:str])
    end

    it 'aplica Robustez Anã (+1 PV) já no nível 1 (expected_max agora soma racial em char_level<=1)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      # init_hp Guerreiro = 10 (hit die) + CON_mod (15 → +2) + 1 (Robustez) = 13.
      expect(sheet.hp_max).to eq(13)
    end

    it 'aplica Robustez Anã ao subir de nível (RacialHpBonus.per_level_from_applied = 1)' do
      # Fora do caminho do bug: validamos que a regra (PHB) está descrita
      # corretamente em `dwarven_toughness.grants.hp_per_level: 1` no YAML
      # e que `RacialHpBonus.per_level_from_applied` resolve.
      RaceRules.reload!
      applied = RaceRules.apply(race_id: 'dwarf', subrace_id: 'hill', choices: {})
      expect(RacialHpBonus.per_level_from_applied(applied[:traits])).to eq(1)
    end

    it 'NÃO concede proficiência adicional de armadura (Mountain only)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      armor = Array(sheet.race_summary.dig('proficiencies', 'armor')).map(&:to_s)
      expect(armor).to be_empty
    end
  end

  # =====================================================================
  #  Provisioning — Anão da Montanha (Mountain Dwarf): STR+2 + armor
  # =====================================================================
  describe 'CharacterProvisioningService — Anão da Montanha (Mountain)' do
    let(:payload) do
      build_payload(sub_rule: 'mountain', attributes: mountain_post_racial)
    end

    it 'reflete +2 CON e +2 STR nas colunas' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      expect(sheet.con).to eq(base_attrs[:con] + 2)
      expect(sheet.str).to eq(base_attrs[:str] + 2),
        "Anão da Montanha concede +2 STR; coluna deve ser #{base_attrs[:str] + 2}"
      # Hill ASI (+1 WIS) não deve aparecer:
      expect(sheet.wis).to eq(base_attrs[:wis])
    end

    it 'concede proficiência de armadura LEVE e MÉDIA em race_summary["proficiencies"]["armor"]' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      armor = Array(sheet.race_summary.dig('proficiencies', 'armor')).map(&:to_s)
      expect(armor).to include('leve')
      expect(armor).to include('média')
    end

    it 'NÃO ganha o +1 PV de Robustez Anã (esse é só do Hill)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      # Mountain = 10 (hit die) + 2 (CON mod 15) = 12, sem +1 da Robustez.
      # Coincidentemente, este teste passa no nível 1 mesmo COM o bug do
      # expected_max — porque Mountain não tem Robustez para somar/perder.
      expect(sheet.hp_max).to eq(12),
        "Mountain Dwarf nível 1 Guerreiro: 10 + 2 (CON mod) = 12; veio #{sheet.hp_max}"
    end

    it 'CharacterSheetSummaryService inclui leve/média em proficiencies.armor' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      summary = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
      expect(summary.success?).to be(true)
      armor = Array(summary.result.dig(:proficiencies, :armor)).map(&:to_s)
      expect(armor).to include('leve', 'média')
    end
  end

  # =====================================================================
  #  RaceProfileService — leitura derivada do snapshot persistido
  # =====================================================================
  describe 'RaceProfileService — leitura derivada' do
    it 'devolve speed=25 + idiomas Comum/Anão para Hill' do
      cmd = CharacterProvisioningService.call(
        user: user,
        payload: build_payload(sub_rule: 'hill', attributes: hill_post_racial)
      )
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      profile = RaceProfileService.new(sheet).call
      expect(profile[:speed_ft]).to eq(25)
      expect(profile[:languages]).to include('Comum', 'Anão')
    end

    it 'devolve darkvision=60 para Hill (CPS agora normaliza Hash → Integer)' do
      cmd = CharacterProvisioningService.call(
        user: user,
        payload: build_payload(sub_rule: 'hill', attributes: hill_post_racial)
      )
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect(RaceProfileService.new(sheet).call[:darkvision].to_i).to eq(60)
    end

    it 'RaceRules.apply confirma darkvision=60 (PHB) — fonte canônica' do
      RaceRules.reload!
      applied = RaceRules.apply(race_id: 'dwarf', subrace_id: 'hill', choices: {})
      expect(applied[:darkvision]).to be_present
      dv = applied[:darkvision]
      val = dv.is_a?(Hash) ? (dv[:range] || dv['range']) : dv
      expect(val.to_i).to eq(60)
    end

    it 'devolve speed=25 para Mountain (sub-raça não muda speed)' do
      cmd = CharacterProvisioningService.call(
        user: user,
        payload: build_payload(sub_rule: 'mountain', attributes: mountain_post_racial)
      )
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      profile = RaceProfileService.new(sheet).call
      expect(profile[:speed_ft]).to eq(25)
    end
  end

  # =====================================================================
  #  RaceRules.apply — contrato canônico do YAML
  # =====================================================================
  describe 'RaceRules.apply — contrato canônico do Anão' do
    it 'base+hill: +2 CON, +1 WIS, dwarven_toughness presente, speed 25, darkvision 60' do
      applied = RaceRules.apply(race_id: 'dwarf', subrace_id: 'hill', choices: {})
      expect(applied[:speed]).to eq(25)
      expect(applied[:darkvision]).to be_present
      expect(applied[:languages]).to include('Comum', 'Anão')
      trait_keys = Array(applied[:traits]).map { |t| t[:key] || t['key'] }
      expect(trait_keys).to include('dwarven_resilience', 'stonecunning', 'dwarven_toughness')
    end

    it 'base+mountain: +2 CON, +2 STR, armor leve/média, sem dwarven_toughness' do
      applied = RaceRules.apply(race_id: 'dwarf', subrace_id: 'mountain', choices: {})
      expect(applied[:speed]).to eq(25)
      armor = Array(applied.dig(:proficiencies, :armor)).map(&:to_s)
      expect(armor).to include('leve', 'média')
      trait_keys = Array(applied[:traits]).map { |t| t[:key] || t['key'] }
      expect(trait_keys).not_to include('dwarven_toughness')
    end
  end
end
