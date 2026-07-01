# frozen_string_literal: true

require 'rails_helper'

# Garante que `CharacterSheetSummaryService#build_proficiencies` mescla as
# proficiências raciais (armas/armaduras/ferramentas fixas) e os picks gravados
# pelo wizard em `metadata.race_choices.chosenTools` — corrige Anão escolhendo
# "Ferramentas de ferreiro" e armas raciais (machado/martelo) que sumiam da ficha.
RSpec.describe CharacterSheetSummaryService, '.build_proficiencies merges race profs' do
  let!(:role) { Role.find_or_create_by!(name: 'player') }
  let(:user) do
    User.create!(
      email: "css_pp_#{SecureRandom.hex(4)}@example.com",
      username: "csspp#{SecureRandom.hex(4)}",
      password: 'password1',
      password_confirmation: 'password1',
      role_id: role.id
    )
  end

  let!(:dwarf_race) { Race.find_or_create_by!(api_index: 'dwarf') { |r| r.name = 'Anão' } }
  let!(:hill_subrace) do
    SubRace.find_or_create_by!(race_id: dwarf_race.id, api_index: 'hill') { |s| s.name = 'Anão da Colina' }
  end
  # Meio-Elfo: usado pelos testes de `chosenSkills` (tem cota racial de 2 perícias
  # à escolha). Sob a regra de raças `cap_race_choice_skills`, picks só contam até
  # a cota REAL da raça — Anão da Colina tem 0, então o fixture desses testes
  # precisa de uma raça com escolha de perícia de fato.
  let!(:half_elf_race) { Race.find_or_create_by!(api_index: 'half_elf') { |r| r.name = 'Meio-Elfo' } }
  let!(:klass) do
    Klass.find_or_create_by!(api_index: 'fighter') do |k|
      k.name = 'Guerreiro'
      k.hit_die = 10
      k.subclass_level = 3
    end
  end

  def build_sheet(meta_overrides: {}, race_summary_overrides: {}, race_id: nil, sub_race_id: :default)
    character = Character.create!(user: user, name: 'Spec PC', background: 'Test')
    race_id ||= dwarf_race.id
    sub_race_id = hill_subrace.id if sub_race_id == :default
    race_summary = {
      'name' => 'Anão',
      'race_name' => 'Anão',
      'sub_race_name' => 'Anão da Colina',
      'speed_ft' => 25,
      'languages' => %w[Comum Anão],
      'proficiencies' => {
        'weapons' => ['machado de batalha', 'machadinha', 'martelo leve', 'martelo de guerra'],
        'tools' => {
          'choiceCount' => 1,
          'choices' => ['Ferramentas de ferreiro', 'Suprimentos de cervejeiro', 'Ferramentas de pedreiro']
        }
      }
    }.deep_merge(race_summary_overrides)

    metadata = {
      'race_choices' => { 'chosenTools' => ['Ferramentas de ferreiro'], 'chosenLanguages' => [] },
      'class_choices' => {}
    }.deep_merge(meta_overrides)

    sheet = Sheet.create!(
      character: character,
      race_id: race_id,
      sub_race_id: sub_race_id,
      str: 14, dex: 12, con: 16, int: 10, wis: 14, cha: 8,
      hp_max: 12, hp_current: 12,
      race_summary: race_summary,
      class_summary: {},
      background_summary: { 'name' => 'Marinheiro', 'tools' => ['Ferramentas de navegador', 'Veículos Aquáticos'] },
      metadata: metadata
    )
    SheetKlass.create!(sheet: sheet, klass: klass, level: 1)
    sheet
  end

  it 'inclui as armas raciais do Anão em proficiencies.weapons' do
    sheet = build_sheet
    cmd = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
    expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }
    weapons = Array(cmd.result.dig(:proficiencies, :weapons)).map(&:to_s)
    expect(weapons).to include('machado de batalha', 'machadinha', 'martelo leve', 'martelo de guerra')
  end

  it 'inclui o pick chosenTools (Ferramentas de ferreiro) em proficiencies.tools' do
    sheet = build_sheet
    cmd = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
    expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }
    tools = Array(cmd.result.dig(:proficiencies, :tools)).map(&:to_s)
    expect(tools).to include('Ferramentas de ferreiro')
    # background tools continuam presentes
    expect(tools).to include('Ferramentas de navegador', 'Veículos Aquáticos')
  end

  it 'inclui tools.fixed quando race_summary.proficiencies.tools já vem resolvido (CPS)' do
    sheet = build_sheet(race_summary_overrides: {
      'proficiencies' => { 'tools' => { 'fixed' => ['Ferramentas de ferreiro'] } }
    }, meta_overrides: { 'race_choices' => { 'chosenTools' => [] } })
    cmd = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
    expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }
    tools = Array(cmd.result.dig(:proficiencies, :tools)).map(&:to_s)
    expect(tools).to include('Ferramentas de ferreiro')
  end

  it 'mantém compat com chave legada race_choices.dwarfTool' do
    sheet = build_sheet(meta_overrides: {
      'race_choices' => { 'chosenTools' => [], 'dwarfTool' => 'Suprimentos de cervejeiro' }
    })
    cmd = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
    expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }
    tools = Array(cmd.result.dig(:proficiencies, :tools)).map(&:to_s)
    expect(tools).to include('Suprimentos de cervejeiro')
  end

  it 'inclui race_choices.chosenSkills em proficiencies.skills.race (Meio-Elfo / Humano Variante)' do
    # Meio-Elfo: 2 perícias à escolha (dentro da cota → cap permite ambas).
    sheet = build_sheet(race_id: half_elf_race.id, sub_race_id: nil, meta_overrides: {
      'race_choices' => {
        'chosenTools' => [],
        'chosenLanguages' => [],
        'chosenSkills' => %w[Enganação Sobrevivência]
      }
    })
    cmd = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
    expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }
    race_skills = Array(cmd.result.dig(:proficiencies, :skills, :race)).map(&:to_s)
    expect(race_skills).to include('Enganação', 'Sobrevivência')
  end

  it 'aceita race_choices.chosen_skills (snake_case) para proficiencies.skills.race' do
    sheet = build_sheet(race_id: half_elf_race.id, sub_race_id: nil, meta_overrides: {
      'race_choices' => {
        'chosenTools' => [],
        'chosen_skills' => ['História']
      }
    })
    cmd = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
    expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }
    race_skills = Array(cmd.result.dig(:proficiencies, :skills, :race)).map(&:to_s)
    expect(race_skills).to include('História')
  end
end

# SubKlass#levels_json (subclass_overrides import) — grants.proficiencies.tools
RSpec.describe CharacterSheetSummaryService, '.build_proficiencies merges subclass tool grants' do
  let!(:role) { Role.find_or_create_by!(name: 'player') }
  let(:user) do
    User.create!(
      email: "css_subtool_#{SecureRandom.hex(4)}@example.com",
      username: "csstool#{SecureRandom.hex(4)}",
      password: 'password1',
      password_confirmation: 'password1',
      role_id: role.id
    )
  end

  let!(:human_race) { Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' } }
  let!(:wizard) do
    Klass.find_or_create_by!(api_index: 'wizard') do |k|
      k.name = 'Mago'
      k.hit_die = 6
      k.subclass_level = 2
    end
  end

  let!(:bard) do
    Klass.find_or_create_by!(api_index: 'bard') do |k|
      k.name = 'Bardo'
      k.hit_die = 8
      k.subclass_level = 3
    end
  end

  # SubKlass cujo grant de proficiência está ANINHADO dentro de uma feature
  # (`row['features'][i]['grants']`) e NÃO em `row['grants']` — ~20 level-rows
  # reais (Colégio da Bravura/Conhecimento/Comédia/..., Domínio da Água/Ar)
  # usam esse formato. Antes do fix essas proficiências eram descartadas.
  def build_bard_valor_sheet(level:)
    sub = SubKlass.create!(
      klass: bard,
      api_index: "colegio-da-bravura-spec-#{SecureRandom.hex(3)}",
      name: 'Colégio da Bravura (spec)',
      levels_json: [
        {
          'level' => 3,
          'features' => [
            {
              'name' => 'Proficiência Adicional',
              'grants' => {
                'proficiencies' => {
                  'armor' => ['armaduras médias', 'escudos'],
                  'weapons' => ['armas marciais'],
                },
              },
            },
          ],
        },
        {
          # grant aninhado num nível ACIMA — só deve aparecer a partir do L14
          'level' => 14,
          'features' => [
            {
              'name' => 'Proficiência Tardia (spec)',
              'grants' => { 'proficiencies' => { 'armor' => ['armadura pesada (spec L14)'] } },
            },
          ],
        },
      ].to_json
    )
    character = Character.create!(user: user, name: 'Bardo PC', background: 'Test')
    sheet = Sheet.create!(
      character: character,
      race_id: human_race.id,
      str: 8, dex: 14, con: 12, int: 10, wis: 12, cha: 16,
      hp_max: 8, hp_current: 8,
      class_summary: {},
      metadata: { 'class_choices' => {} }
    )
    SheetKlass.create!(sheet: sheet, klass: bard, sub_klass: sub, level: level)
    sheet
  end

  it 'inclui tools concedidas pela subclasse (ex.: Maestria dos Autômatos) em proficiencies.tools' do
    sub = SubKlass.create!(
      klass: wizard,
      api_index: 'maestria-dos-automatos-spec',
      name: 'Maestria dos Autômatos (spec)',
      levels_json: [
        {
          'level' => 2,
          'grants' => {
            'proficiencies' => {
              'tools' => [
                'Ferramentas de Coureiro',
                'Ferramentas de Entalhador',
                'Ferramentas de Ferreiro',
                'Ferramentas de Funileiro',
              ],
            },
          },
        }
      ].to_json
    )
    character = Character.create!(user: user, name: 'Wiz PC', background: 'Test')
    sheet = Sheet.create!(
      character: character,
      race_id: human_race.id,
      str: 8, dex: 14, con: 14, int: 16, wis: 12, cha: 8,
      hp_max: 8, hp_current: 8,
      class_summary: { 'tools' => [] },
      metadata: { 'class_choices' => {} }
    )
    SheetKlass.create!(sheet: sheet, klass: wizard, sub_klass: sub, level: 2)
    cmd = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
    expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }
    tools = Array(cmd.result.dig(:proficiencies, :tools)).map(&:to_s)
    expect(tools).to include(
      'Ferramentas de Coureiro',
      'Ferramentas de Entalhador',
      'Ferramentas de Ferreiro',
      'Ferramentas de Funileiro',
    )
  end

  it 'resolve grants.proficiencies.weapons com choose/options pela escolha do per_level' do
    sub = SubKlass.create!(
      klass: wizard,
      api_index: 'feiticeiro-da-espada-spec',
      name: 'Feitiçaria da Espada (spec)',
      levels_json: [
        {
          'level' => 2,
          'grants' => {
            'proficiencies' => {
              'weapons' => {
                'choose' => 1,
                'options' => ['espada curta', 'espada longa', 'cimitarra']
              }
            }
          }
        }
      ].to_json
    )
    character = Character.create!(user: user, name: 'Sword PC', background: 'Test')
    sheet = Sheet.create!(
      character: character,
      race_id: human_race.id,
      str: 8, dex: 14, con: 14, int: 16, wis: 12, cha: 8,
      hp_max: 8, hp_current: 8,
      class_summary: { 'weapon_proficiencies' => [] },
      metadata: {
        'class_choices' => {
          'per_level' => {
            '2' => { 'weapon' => ['Espada Longa'] }
          }
        }
      }
    )
    SheetKlass.create!(sheet: sheet, klass: wizard, sub_klass: sub, level: 2)
    cmd = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
    expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }
    weapons = Array(cmd.result.dig(:proficiencies, :weapons)).map(&:to_s)
    expect(weapons).to include('Espada Longa')
    expect(weapons.join(' ')).not_to include('choose')
    expect(weapons.join(' ')).not_to include('options')
  end

  it 'mescla grants.proficiencies ANINHADOS em features (Colégio da Bravura L3) em armor/weapons' do
    sheet = build_bard_valor_sheet(level: 5)
    cmd = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
    expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }
    armor = Array(cmd.result.dig(:proficiencies, :armor)).map(&:to_s)
    weapons = Array(cmd.result.dig(:proficiencies, :weapons)).map(&:to_s)
    expect(armor).to include('armaduras médias', 'escudos')
    expect(weapons).to include('armas marciais')
    # guard de nível: o grant aninhado de L14 NÃO aparece num personagem L5
    expect(armor).not_to include('armadura pesada (spec L14)')
  end
end
