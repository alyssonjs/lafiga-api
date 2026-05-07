# frozen_string_literal: true

require 'rails_helper'

# BDD: Criação de personagem com a raça Gnomo (PHB)
# --------------------------------------------------
# Regras (`api/config/race_rules.yml`):
#
#   Gnomo (base):
#     - Médio (no YAML do projeto), 25 ft, darkvision 60
#     - Idiomas: Comum, Gnômico (sem extra)
#     - ASI: +2 INT
#     - Traits: gnome_cunning, darkvision
#
#   Sub-raças:
#     forest (Gnomo da Floresta):
#       - +1 DEX
#       - Traits:
#         * minor_illusion_cantrip — concede a magia "minor-illusion" como
#           cantrip inato (INT, at_will). Persistido via RacialSpellsService
#           em SheetKnownSpell.
#         * speak_with_small_beasts
#     rock (Gnomo das Rochas):
#       - +1 CON
#       - Traits: artificers_lore, tinker
#
# Foco deste arquivo: ASI por sub-raça, darkvision (continuamos cobrindo via
# RaceRules.apply que TEM o dado correto), e principalmente o cantrip racial
# do Gnomo da Floresta — Minor Illusion / Ilusão Menor — verificando que
# RacialSpellsService criou SheetKnownSpell com source='race'.
RSpec.describe 'Criação de Personagem Gnomo (BDD PHB)', type: :service do
  let(:user) { create(:user) }

  let!(:gnome_race) do
    Race.find_or_create_by!(api_index: 'gnome') { |r| r.name = 'Gnomo' }
  end

  let!(:forest_subrace) do
    SubRace.find_or_create_by!(race_id: gnome_race.id, api_index: 'forest') do |s|
      s.name = 'Gnomo da Floresta'
    end
  end

  let!(:rock_subrace) do
    SubRace.find_or_create_by!(race_id: gnome_race.id, api_index: 'rock') do |s|
      s.name = 'Gnomo das Rochas'
    end
  end

  let!(:klass) do
    Klass.find_or_create_by!(api_index: 'wizard') do |k|
      k.name = 'Mago'; k.hit_die = 6; k.subclass_level = 2
    end
  end

  let!(:bg) do
    Background.find_or_create_by!(api_index: 'sage') do |b|
      b.name = 'Sábio'; b.feature_name = 'Pesquisador'; b.feature_desc = 'Spec'
    end
  end

  let!(:align) do
    Alignment.find_or_create_by!(api_index: 'ng') { |a| a.name = 'Neutro e Bom' }
  end

  # `minor-illusion` precisa existir como Spell no DB para o RacialSpellsService
  # poder criar SheetKnownSpell. O CPS resolve por nome (case-insensitive +
  # api_index canônico). Criamos com api_index 'minor-illusion' e nome PT.
  let!(:minor_illusion_spell) do
    Spell.find_or_create_by!(api_index: 'minor-illusion') do |s|
      s.name = 'Ilusão Menor'
      s.level = 0
    end
  end

  # Base 10/13/12/14/10/8.
  #   forest = +INT 2 / +DEX 1   →  10/14/12/16/10/8
  #   rock   = +INT 2 / +CON 1   →  10/13/13/16/10/8
  def base_attrs
    { str: 10, dex: 13, con: 12, int: 14, wis: 10, cha: 8 }
  end

  def post_racial(sub_rule)
    case sub_rule
    when 'forest' then base_attrs.merge(int: base_attrs[:int] + 2, dex: base_attrs[:dex] + 1)
    when 'rock'   then base_attrs.merge(int: base_attrs[:int] + 2, con: base_attrs[:con] + 1)
    end
  end

  def sub_id_for(sub_rule)
    { 'forest' => forest_subrace.id, 'rock' => rock_subrace.id }[sub_rule]
  end

  def build_payload(sub_rule:)
    {
      character: { name: "Spec Gnome #{sub_rule} #{SecureRandom.hex(3)}", background: bg.name },
      wizard: {
        meta: { name: "Spec Gnome #{sub_rule}", alignmentKey: align.api_index },
        race: {
          raceId: gnome_race.id,
          subRaceId: sub_id_for(sub_rule),
          ruleId: 'gnome',
          subRuleId: sub_rule,
          attributes: post_racial(sub_rule),
          raceChoices: {}
        },
        klass: {
          klassId: klass.id,
          level: 1,
          classSkillPicks: %w[Arcanismo Investigação],
          classPicksByLevel: { '1' => { 'hp' => { 'dieResult' => 6, 'total' => 7, 'method' => 'average' } } }
        },
        background: { backgroundName: bg.name, backgroundKey: bg.api_index },
        equipment: {},
        avatar: { customization: {} }
      }
    }
  end

  before { RaceRules.reload! }

  # =====================================================================
  #  Provisioning — Gnomo da Floresta (Forest)
  # =====================================================================
  describe 'CharacterProvisioningService — Gnomo da Floresta (Forest)' do
    let(:payload) { build_payload(sub_rule: 'forest') }

    it 'persiste race_id, sub_race_id, speed=25 e idiomas Comum/Gnômico' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }
      sheet = Sheet.order(:id).last

      expect(sheet.race_id).to eq(gnome_race.id)
      expect(sheet.sub_race_id).to eq(forest_subrace.id)
      rs = sheet.race_summary || {}
      expect(rs['speed_ft'].to_i).to eq(25)
      expect(Array(rs['languages']).map(&:to_s)).to include('Comum', 'Gnômico')
    end

    it 'reflete +2 INT e +1 DEX nas colunas' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect(sheet.int).to eq(base_attrs[:int] + 2)
      expect(sheet.dex).to eq(base_attrs[:dex] + 1)
      expect(sheet.con).to eq(base_attrs[:con]) # Rock CON+1 NÃO aplica
    end

    it 'cria SheetKnownSpell para Ilusão Menor (cantrip racial) com source=race' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      ksk = sheet.sheet_klasses.first
      racial_spells = SheetKnownSpell.where(sheet_klass: ksk, source: 'race').to_a
      names = racial_spells.map { |s| s.spell&.name.to_s.downcase }
      expect(names).to include('ilusão menor'),
        "Forest Gnome deve ter Ilusão Menor como cantrip racial (source=race); " \
        "veio #{names.inspect}"
    end
  end

  # =====================================================================
  #  Provisioning — Gnomo das Rochas (Rock)
  # =====================================================================
  describe 'CharacterProvisioningService — Gnomo das Rochas (Rock)' do
    let(:payload) { build_payload(sub_rule: 'rock') }

    it 'reflete +2 INT e +1 CON nas colunas' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect(sheet.int).to eq(base_attrs[:int] + 2)
      expect(sheet.con).to eq(base_attrs[:con] + 1)
      expect(sheet.dex).to eq(base_attrs[:dex]) # Forest DEX+1 NÃO aplica
    end

    it 'NÃO cria SheetKnownSpell racial (Rock não tem cantrip)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      ksk = sheet.sheet_klasses.first
      racial_spells = SheetKnownSpell.where(sheet_klass: ksk, source: 'race').to_a
      expect(racial_spells).to be_empty,
        'Rock Gnome não tem cantrip racial inato; SheetKnownSpell de race deve ser vazio.'
    end
  end

  # =====================================================================
  #  RaceRules.apply — contrato canônico
  # =====================================================================
  describe 'RaceRules.apply — contrato canônico do Gnomo' do
    it 'forest: +2 INT, +1 DEX, traits incluem minor_illusion_cantrip + speak_with_small_beasts + gnome_cunning + darkvision' do
      applied = RaceRules.apply(race_id: 'gnome', subrace_id: 'forest', choices: {})
      expect(applied[:speed]).to eq(25)
      keys = Array(applied[:traits]).map { |t| t[:key] || t['key'] }
      expect(keys).to include(
        'gnome_cunning', 'darkvision',
        'minor_illusion_cantrip', 'speak_with_small_beasts'
      )

      # innate_spells deve refletir o grant do trait minor_illusion_cantrip:
      spells = Array(applied[:innate_spells]).map { |s| (s[:name] || s['name']).to_s }
      expect(spells).to include('minor-illusion')
    end

    it 'rock: +2 INT, +1 CON, traits incluem artificers_lore + tinker' do
      applied = RaceRules.apply(race_id: 'gnome', subrace_id: 'rock', choices: {})
      expect(applied[:speed]).to eq(25)
      keys = Array(applied[:traits]).map { |t| t[:key] || t['key'] }
      expect(keys).to include('gnome_cunning', 'darkvision', 'artificers_lore', 'tinker')
      # Rock NÃO tem minor_illusion_cantrip:
      expect(keys).not_to include('minor_illusion_cantrip')
    end
  end

  # =====================================================================
  #  GAPs do sistema
  # =====================================================================
  describe 'CPS persiste darkvision em race_summary' do
    it 'darkvision=60 para Gnomo da Floresta' do
      cmd = CharacterProvisioningService.call(user: user, payload: build_payload(sub_rule: 'forest'))
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect((sheet.race_summary || {})['darkvision'].to_i).to eq(60)
    end
  end
end
