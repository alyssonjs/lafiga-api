# frozen_string_literal: true

require 'rails_helper'

# Cobre o override editável do DM `sub_klasses.terrain_spells` (jsonb)
# no agregador de magias. O override deve ter PRECEDÊNCIA sobre o
# `levels_json` canônico (e sobre o fallback YAML) — espelha o
# `getEffectiveTerrainSpells` do front. Sem override, mantém o canônico.
RSpec.describe KnownSpellsAggregator, 'Círculo da Terra terrain_spells override' do
  let(:druid) do
    Klass.find_or_create_by!(api_index: 'druid') do |k|
      k.name = 'Druida Spec'
      k.hit_die = 8
      k.subclass_level = 2
    end
  end

  # levels_json canônico (caminho antigo): concede "Magia Canônica" no nível 3.
  let(:canonical_levels_json) do
    JSON.generate([
      {
        'level' => 3,
        'grants' => {
          'spells' => {
            'always_prepared_by_terrain' => {
              'costa' => { '3' => ['Magia Canonica Spec'] },
            },
          },
        },
      },
    ])
  end

  def make_sheet(level: 5, terrain: 'Costa')
    sheet = create(:sheet, metadata: {
      'class_choices' => { 'per_level' => { '2' => { 'terrain' => terrain } } },
    })
    [sheet, level]
  end

  before do
    # Magias resolvidas por NOME via SpellResolver (contrato preservado).
    create(:spell, name: 'Magia Canonica Spec', level: 2, api_index: "canon_#{SecureRandom.hex(3)}")
    create(:spell, name: 'Magia Override Spec', level: 2, api_index: "ovr_#{SecureRandom.hex(3)}")
    create(:spell, name: 'Magia Override Nv5 Spec', level: 3, api_index: "ovr5_#{SecureRandom.hex(3)}")
  end

  it 'usa terrain_spells (override do DM) e ignora o levels_json canônico' do
    sub = create(:sub_klass, klass: druid, name: 'Círculo da Terra',
                 levels_json: canonical_levels_json,
                 terrain_spells: [
                   {
                     'terrain' => 'Costa',
                     'spells' => [
                       { 'level' => 3, 'spellLevel' => 2, 'spells' => ['Magia Override Spec'] },
                       { 'level' => 5, 'spellLevel' => 3, 'spells' => ['Magia Override Nv5 Spec'] },
                     ],
                   },
                 ])
    sheet, lvl = make_sheet(level: 5)
    create(:sheet_klass, sheet: sheet, klass: druid, sub_klass: sub, level: lvl)

    result = described_class.new(sheet.reload).call
    prepared = result[:prepared_by_level].values.flatten
    names = prepared.map { |e| e[:name] }

    expect(names).to include('Magia Override Spec')
    expect(names).to include('Magia Override Nv5 Spec')
    # Precedência: o canônico do levels_json NÃO entra quando há override.
    expect(names).not_to include('Magia Canonica Spec')
    # Magias do Círculo são marcadas como circle.
    override_entry = prepared.find { |e| e[:name] == 'Magia Override Spec' }
    expect(override_entry[:circle]).to eq(true)
  end

  it 'sem terrain_spells: cai no levels_json canônico' do
    sub = create(:sub_klass, klass: druid, name: 'Círculo da Terra',
                 levels_json: canonical_levels_json,
                 terrain_spells: nil)
    sheet, lvl = make_sheet(level: 5)
    create(:sheet_klass, sheet: sheet, klass: druid, sub_klass: sub, level: lvl)

    result = described_class.new(sheet.reload).call
    names = result[:prepared_by_level].values.flatten.map { |e| e[:name] }

    expect(names).to include('Magia Canonica Spec')
  end

  it 'override respeita o nível do personagem (nv3 não recebe magia de nv5)' do
    sub = create(:sub_klass, klass: druid, name: 'Círculo da Terra',
                 terrain_spells: [
                   {
                     'terrain' => 'Costa',
                     'spells' => [
                       { 'level' => 3, 'spellLevel' => 2, 'spells' => ['Magia Override Spec'] },
                       { 'level' => 5, 'spellLevel' => 3, 'spells' => ['Magia Override Nv5 Spec'] },
                     ],
                   },
                 ])
    sheet, lvl = make_sheet(level: 3)
    create(:sheet_klass, sheet: sheet, klass: druid, sub_klass: sub, level: lvl)

    result = described_class.new(sheet.reload).call
    names = result[:prepared_by_level].values.flatten.map { |e| e[:name] }

    expect(names).to include('Magia Override Spec')        # nível 3 ≤ 3
    expect(names).not_to include('Magia Override Nv5 Spec') # nível 5 > 3
  end

  it 'override para terreno diferente do escolhido não aplica' do
    sub = create(:sub_klass, klass: druid, name: 'Círculo da Terra',
                 levels_json: canonical_levels_json,
                 terrain_spells: [
                   {
                     'terrain' => 'Deserto',
                     'spells' => [
                       { 'level' => 3, 'spellLevel' => 2, 'spells' => ['Magia Override Spec'] },
                     ],
                   },
                 ])
    sheet, lvl = make_sheet(level: 5, terrain: 'Costa')
    create(:sheet_klass, sheet: sheet, klass: druid, sub_klass: sub, level: lvl)

    result = described_class.new(sheet.reload).call
    names = result[:prepared_by_level].values.flatten.map { |e| e[:name] }

    # Override não casa o terreno escolhido → cai no canônico.
    expect(names).not_to include('Magia Override Spec')
    expect(names).to include('Magia Canonica Spec')
  end
end
