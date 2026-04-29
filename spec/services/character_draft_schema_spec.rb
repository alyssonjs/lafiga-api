# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CharacterDraftSchema do
  describe '.migrate' do
    it 'sets _version on legacy blobs (idempotent)' do
      out = described_class.migrate({})
      expect(out['_version']).to eq(described_class::DRAFT_SCHEMA_VERSION)
      out2 = described_class.migrate(out)
      expect(out2['_version']).to eq(described_class::DRAFT_SCHEMA_VERSION)
    end

    it 'fills default arrays/hashes for missing keys' do
      out = described_class.migrate({})
      expect(out['raceChoices']).to eq({})
      expect(out['levelChoices']).to eq([])
      expect(out['spellSelections']).to include('cantrips' => [], 'known' => [], 'spellbook' => [], 'prepared' => [])
      expect(out['progressionSubLevel']).to eq(1)
    end

    it 'preserves unknown keys (passthrough)' do
      out = described_class.migrate({ 'foo' => { 'bar' => 1 } })
      expect(out['foo']).to eq({ 'bar' => 1 })
    end

    it 'coerces level/isNPC to canonical types' do
      out = described_class.migrate({ 'level' => '5', 'isNPC' => 'true' })
      expect(out['level']).to eq(5)
      expect(out['isNPC']).to eq(true)
    end
  end

  describe '.read_step' do
    let(:data) do
      {
        'name' => 'Aria',
        'level' => 3,
        'selectedRace' => { 'id' => '1' },
        'raceChoices' => { 'chosenLanguages' => ['Anão'] },
        'level1Choices' => { 'expertise' => ['Acrobacia'] },
        'selectedSkills' => ['Furtividade']
      }
    end

    it 'returns just the general fragment' do
      expect(described_class.read_step(data, 'general')).to include('name' => 'Aria', 'level' => 3)
      expect(described_class.read_step(data, 'general')).not_to have_key('selectedRace')
    end

    it 'returns expertise alongside selectedSkills for skills step' do
      out = described_class.read_step(data, 'skills')
      expect(out['selectedSkills']).to eq(['Furtividade'])
      expect(out['expertise']).to eq(['Acrobacia'])
    end
  end
end
