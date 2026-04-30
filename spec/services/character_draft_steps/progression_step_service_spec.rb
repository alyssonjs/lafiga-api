# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CharacterDraftSteps::ProgressionStepService do
  let(:user) { create(:user) }
  let(:character) { create(:character, user: user, status: :draft) }

  it 'writes only the targeted level when `level` is provided' do
    character.update!(draft_data: {
      'level' => 5,
      'levelChoices' => [
        { 'level' => 2, 'hp' => { 'method' => 'max', 'total' => 8 } },
        { 'level' => 3, 'hp' => { 'method' => 'average', 'total' => 5 } }
      ]
    })

    svc = described_class.new(
      character: character,
      data: { 'levelChoice' => { 'hp' => { 'method' => 'rolled', 'total' => 7 } } },
      level: 3
    )
    result = svc.call

    lcs = result.draft_data['levelChoices']
    expect(lcs.length).to eq(2)
    expect(lcs.find { |r| r['level'] == 2 }['hp']['total']).to eq(8) # untouched
    expect(lcs.find { |r| r['level'] == 3 }['hp']['method']).to eq('rolled')
  end

  it 'inserts in order when targeting a new level' do
    character.update!(draft_data: { 'level' => 5, 'levelChoices' => [{ 'level' => 2 }] })

    svc = described_class.new(character: character, data: { 'levelChoice' => { 'hp' => { 'total' => 6 } } }, level: 4)
    result = svc.call

    expect(result.draft_data['levelChoices'].map { |r| r['level'] }).to eq([2, 4])
  end

  it 'replaces full array when level is omitted (legacy bulk)' do
    character.update!(draft_data: { 'levelChoices' => [{ 'level' => 2 }] })
    svc = described_class.new(character: character, data: { 'levelChoices' => [{ 'level' => 5 }] })
    result = svc.call
    expect(result.draft_data['levelChoices']).to eq([{ 'level' => 5 }])
  end

  it 'updates spellSelections as side-effect' do
    svc = described_class.new(character: character, data: { 'spellSelections' => { 'cantrips' => ['s1'] } })
    result = svc.call
    expect(result.draft_data['spellSelections']['cantrips']).to eq(['s1'])
  end

  # ZX3 do segundo audit (paridade com B7.1/B7.2 do ProgressionEditService):
  # Antes era `existing[idx] = row` direto + `merged['spellSelections'] = ...`
  # direto. PATCH parcial editando so `hp` do nivel 4 descartava `feat`,
  # `expertise`, `subclassChoice` etc. Idem para spellSelections com so cantrips.
  describe 'ZX3 — deep_merge em level/spell PATCH parcial' do
    it 'preserva feat/expertise quando PATCH parcial edita so hp do mesmo nivel' do
      character.update!(draft_data: {
        'level' => 5,
        'levelChoices' => [
          {
            'level' => 4,
            'hp' => { 'method' => 'average', 'total' => 6 },
            'feat' => { 'name' => 'Observador' },
            'expertise' => ['perception'],
            'subclassChoice' => { 'id' => 'sub-1' }
          }
        ]
      })

      svc = described_class.new(
        character: character,
        data: { 'levelChoice' => { 'hp' => { 'method' => 'rolled', 'total' => 8 } } },
        level: 4
      )
      result = svc.call

      row = result.draft_data['levelChoices'].find { |r| r['level'] == 4 }
      expect(row['hp']).to eq('method' => 'rolled', 'total' => 8)
      expect(row['feat']).to eq('name' => 'Observador')        # preservado
      expect(row['expertise']).to eq(['perception'])           # preservado
      expect(row['subclassChoice']).to eq('id' => 'sub-1')     # preservado
    end

    it 'substitui o asi inteiro ao trocar talento por atributo no mesmo nivel' do
      character.update!(draft_data: {
        'level' => 5,
        'levelChoices' => [
          {
            'level' => 4,
            'asi' => {
              'mode' => 'feat',
              'featId' => 'observador',
              'choices' => { 'ability' => 'wis' }
            }
          }
        ]
      })

      svc = described_class.new(
        character: character,
        data: { 'levelChoice' => { 'asiChoice' => { 'mode' => 'plus2', 'ability1' => 'cha' } } },
        level: 4
      )
      result = svc.call

      row = result.draft_data['levelChoices'].find { |r| r['level'] == 4 }
      expect(row['asi']).to eq('mode' => 'plus2', 'ability1' => 'cha')
      expect(row).not_to have_key('asiChoice')
    end

    it 'preserva known/spellbook/prepared quando PATCH parcial edita so cantrips' do
      character.update!(draft_data: {
        'spellSelections' => {
          'cantrips' => %w[fire_bolt mage_hand],
          'known' => %w[magic_missile shield],
          'spellbook' => %w[magic_missile shield burning_hands],
          'prepared' => %w[magic_missile]
        }
      })

      svc = described_class.new(
        character: character,
        data: { 'spellSelections' => { 'cantrips' => %w[fire_bolt mage_hand light] } }
      )
      result = svc.call

      sel = result.draft_data['spellSelections']
      expect(sel['cantrips']).to eq(%w[fire_bolt mage_hand light])
      expect(sel['known']).to eq(%w[magic_missile shield])      # preservado
      expect(sel['spellbook']).to eq(%w[magic_missile shield burning_hands]) # preservado
      expect(sel['prepared']).to eq(%w[magic_missile])           # preservado
    end

    it 'permite zerar sub-aba especifica de spellSelections via array vazio' do
      character.update!(draft_data: {
        'spellSelections' => {
          'cantrips' => %w[fire_bolt],
          'known' => %w[magic_missile shield],
          'spellbook' => [],
          'prepared' => []
        }
      })

      svc = described_class.new(
        character: character,
        data: { 'spellSelections' => { 'known' => [] } }
      )
      result = svc.call

      sel = result.draft_data['spellSelections']
      expect(sel['known']).to eq([])                # zerado explicitamente
      expect(sel['cantrips']).to eq(%w[fire_bolt])  # preservado
    end
  end
end
