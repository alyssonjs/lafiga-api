# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LevelChoiceNormalizer do
  describe '.normalize_row' do
    it 'returns the row unchanged when there is no asiChoice' do
      row = { 'level' => 4, 'hp' => { 'total' => 7 } }
      expect(described_class.normalize_row(row)).to eq(row)
    end

    it 'translates plus2 asiChoice to canonical asi shape' do
      row = {
        'level' => 4,
        'asiChoice' => { 'mode' => 'plus2', 'ability1' => 'str' }
      }
      out = described_class.normalize_row(row)
      expect(out).not_to have_key('asiChoice')
      expect(out['asi']).to eq('mode' => 'plus2', 'ability1' => 'str')
    end

    it 'translates plus1x2 asiChoice with both abilities' do
      row = {
        'asiChoice' => { 'mode' => 'plus1x2', 'ability1' => 'wis', 'ability2' => 'con' }
      }
      out = described_class.normalize_row(row)
      expect(out['asi']).to include('mode' => 'plus1x2', 'ability1' => 'wis', 'ability2' => 'con')
    end

    it 'translates feat asiChoice including featAbility into choices.ability' do
      row = {
        'asiChoice' => {
          'mode' => 'feat',
          'featId' => 'feat-resilient',
          'featAbility' => 'con'
        }
      }
      out = described_class.normalize_row(row)
      expect(out['asi']).to include(
        'mode' => 'feat',
        'featId' => 'feat-resilient',
        'featAbility' => 'con',
        'choices' => { 'ability' => 'con' }
      )
    end

    it 'renames featGrantChoices.skills to choices.proficiencies' do
      row = {
        'asiChoice' => {
          'mode' => 'feat',
          'featId' => 'feat-skilled',
          'featGrantChoices' => { 'skills' => %w[Atletismo Acrobacia] }
        }
      }
      out = described_class.normalize_row(row)
      expect(out['asi']['choices']).to eq('proficiencies' => %w[Atletismo Acrobacia])
    end

    it 'preserves cantrips/spells/languages keys verbatim' do
      row = {
        'asiChoice' => {
          'mode' => 'feat',
          'featId' => 'feat-magic-initiate',
          'featGrantChoices' => {
            'cantrips' => %w[Fire-Bolt],
            'spells'   => %w[Magic-Missile],
            'languages' => %w[elven]
          }
        }
      }
      out = described_class.normalize_row(row)
      expect(out['asi']['choices']).to include(
        'cantrips' => %w[Fire-Bolt],
        'spells'   => %w[Magic-Missile],
        'languages' => %w[elven]
      )
    end

    it 'is idempotent when row already carries asi' do
      row = {
        'asi' => { 'mode' => 'plus2', 'ability1' => 'dex' }
      }
      out = described_class.normalize_row(row)
      expect(out).to eq(row)
    end

    it 'symbol keys also work (deep_stringify)' do
      row = { asiChoice: { mode: 'plus2', ability1: 'cha' } }
      out = described_class.normalize_row(row)
      expect(out['asi']).to eq('mode' => 'plus2', 'ability1' => 'cha')
    end
  end
end
