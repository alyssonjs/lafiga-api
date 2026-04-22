# frozen_string_literal: true

require 'rails_helper'

# Garante que o `race_summary` persistido na sheet é completo: usa applied[:speed]
# e applied[:proficiencies] do RaceRules.apply (resolve Wood Elf 35 ft e perícia
# de Percepção concedida pelo Elfo base).
RSpec.describe CharacterProvisioningService, type: :service do
  let(:user) { create(:user) }

  let!(:elf_race) do
    Race.find_or_create_by!(api_index: 'elf') { |r| r.name = 'Elfo' }
  end

  let!(:wood_subrace) do
    SubRace.find_or_create_by!(race_id: elf_race.id, api_index: 'wood') { |s| s.name = 'Elfo da Floresta' }
  end

  let!(:klass) do
    Klass.find_or_create_by!(api_index: 'fighter') do |k|
      k.name = 'Guerreiro'
      k.hit_die = 10
      k.subclass_level = 3
    end
  end

  let!(:bg) do
    Background.find_or_create_by!(api_index: 'soldier') do |b|
      b.name = 'Soldado'
      b.feature_name = 'Patente Militar'
      b.feature_desc = 'Spec'
    end
  end

  let!(:align) { Alignment.find_or_create_by!(api_index: 'lg') { |a| a.name = 'Leal e Bom' } }

  let(:payload) do
    {
      character: { name: "RSpec WoodElf #{SecureRandom.hex(3)}", background: bg.name },
      wizard: {
        meta: { name: 'RSpec WoodElf', alignmentKey: align.api_index },
        race: {
          raceId: elf_race.id,
          subRaceId: wood_subrace.id,
          ruleId: 'elf',
          subRuleId: 'wood',
          attributes: { str: 14, dex: 16, con: 14, int: 10, wis: 12, cha: 10 },
          raceChoices: { chosenLanguages: [] }
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

  it 'persiste race_summary[:speed_ft] = 35 para Wood Elf (sub-raça sobrescreve speed base)' do
    cmd = described_class.call(user: user, payload: payload)
    expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }

    sheet = Sheet.order(:id).last
    rs = sheet.race_summary || {}
    expect(rs['speed_ft'].to_i).to eq(35)
  end

  it 'persiste perícias raciais (Percepção do Elfo) em race_summary["proficiencies"]["skills"]' do
    cmd = described_class.call(user: user, payload: payload)
    expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }

    sheet = Sheet.order(:id).last
    rs = sheet.race_summary || {}
    profs = rs['proficiencies'] || {}
    skills = profs['skills']
    fixed = skills.is_a?(Hash) ? Array(skills['fixed']) : Array(skills)
    expect(fixed).to include('Percepção')
  end

  context 'Anão da Colina com pick de ferramenta' do
    let!(:dwarf_race) { Race.find_or_create_by!(api_index: 'dwarf') { |r| r.name = 'Anão' } }
    let!(:hill_subrace) do
      SubRace.find_or_create_by!(race_id: dwarf_race.id, api_index: 'hill') { |s| s.name = 'Anão da Colina' }
    end

    let(:dwarf_payload) do
      {
        character: { name: "RSpec Dwarf #{SecureRandom.hex(3)}", background: bg.name },
        wizard: {
          meta: { name: 'RSpec Dwarf', alignmentKey: align.api_index },
          race: {
            raceId: dwarf_race.id,
            subRaceId: hill_subrace.id,
            ruleId: 'dwarf',
            subRuleId: 'hill',
            attributes: { str: 14, dex: 12, con: 16, int: 10, wis: 14, cha: 8 },
            raceChoices: { chosenTools: ['Ferramentas de ferreiro'], chosenLanguages: [] }
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

    it 'persiste armas raciais do Anão em race_summary["proficiencies"]["weapons"]' do
      cmd = described_class.call(user: user, payload: dwarf_payload)
      expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }

      sheet = Sheet.order(:id).last
      rs = sheet.race_summary || {}
      weapons = Array((rs['proficiencies'] || {})['weapons']).map(&:to_s)
      expect(weapons).to include('machado de batalha', 'machadinha', 'martelo leve', 'martelo de guerra')
    end

    it 'resolve chosenTools dentro de race_summary["proficiencies"]["tools"]["fixed"]' do
      cmd = described_class.call(user: user, payload: dwarf_payload)
      expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }

      sheet = Sheet.order(:id).last
      rs = sheet.race_summary || {}
      tools = (rs['proficiencies'] || {})['tools'] || {}
      expect(tools).to be_a(Hash)
      expect(Array(tools['fixed'])).to include('Ferramentas de ferreiro')
      # mantém auditoria do menu original
      expect(Array(tools['choices'])).to include('Ferramentas de ferreiro', 'Suprimentos de cervejeiro', 'Ferramentas de pedreiro')
    end
  end
end
