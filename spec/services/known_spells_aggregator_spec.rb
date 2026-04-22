# frozen_string_literal: true

require 'rails_helper'

RSpec.describe KnownSpellsAggregator do
  describe '#call' do
    it 'returns known spells grouped by level for persisted SheetKnownSpell rows' do
      sheet = create(:sheet)
      sk = create(:sheet_klass, sheet: sheet)
      sp0 = create(:spell, level: 0, name: 'Zap Cantrip')
      sp1 = create(:spell, level: 1, name: 'Spec Magic Missile')
      create(:sheet_known_spell, sheet_klass: sk, spell: sp0)
      create(:sheet_known_spell, sheet_klass: sk, spell: sp1)

      result = described_class.new(sheet).call

      expect(result[:known_by_level][0].map { |e| e[:id] }).to include(sp0.id)
      expect(result[:known_by_level][1].map { |e| e[:id] }).to include(sp1.id)
      expect(result[:catalog_by_id][sp0.id][:name]).to eq('Zap Cantrip')
    end
  end
end
