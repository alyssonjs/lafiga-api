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

    it 'em conjurador known (Ranger), metadata spell_selections substitui SheetKnownSpell defasado' do
      ranger = create(:klass, api_index: 'ranger', name: 'Ranger Spec')
      sp_old = create(:spell, level: 1, name: 'Old KSA', api_index: "ksa_old_#{SecureRandom.hex(3)}")
      sp_new = create(:spell, level: 1, name: 'New KSA', api_index: "ksa_new_#{SecureRandom.hex(3)}")
      sheet = create(:sheet, metadata: {
        'spell_selections' => {
          'cantrips' => [],
          'known' => [sp_new.id.to_s],
          'spellbook' => [],
          'prepared' => []
        }
      })
      sk = create(:sheet_klass, sheet: sheet, klass: ranger, level: 9)
      create(:sheet_known_spell, sheet_klass: sk, spell: sp_old)

      result = described_class.new(sheet.reload).call
      ids = (result[:known_by_level].values.flatten.map { |e| e[:id] }).compact
      expect(ids).to eq([sp_new.id])
      expect(ids).not_to include(sp_old.id)
    end

    it 'com spell_selections vazio, nao reidrata spells de per_level para known caster' do
      ranger = create(:klass, api_index: 'ranger', name: 'Ranger Spec 2')
      sp_per = create(:spell, level: 1, name: 'Per Only', api_index: "ksa_per_#{SecureRandom.hex(3)}")
      sheet = create(:sheet, metadata: {
        'class_choices' => { 'per_level' => { '2' => { 'spells' => [{ 'name' => sp_per.name, 'level' => 1 }] } } },
        'spell_selections' => {
          'cantrips' => [],
          'known' => [],
          'spellbook' => [],
          'prepared' => []
        }
      })
      create(:sheet_klass, sheet: sheet, klass: ranger, level: 5)

      result = described_class.new(sheet.reload).call
      expect(result[:known_by_level].values.flatten).to eq([])
    end
  end
end
