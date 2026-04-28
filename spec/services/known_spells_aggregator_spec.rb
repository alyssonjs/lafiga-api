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

    it 'inclui known_source nas entradas quando SheetKnownSpell tem fonte (race)' do
      sheet = create(:sheet)
      sk = create(:sheet_klass, sheet: sheet)
      sp0 = create(:spell, level: 0, name: 'Zap Racial', api_index: "zap_racial_#{SecureRandom.hex(3)}")
      create(:sheet_known_spell, sheet_klass: sk, spell: sp0, source: 'race')

      result = described_class.new(sheet).call
      row = result[:known_by_level][0].find { |e| e[:id] == sp0.id }
      expect(row[:known_source]).to eq('race')
      expect(row[:sheet_known_spell_id]).to eq(SheetKnownSpell.find_by!(spell_id: sp0.id, sheet_klass_id: sk.id).id)
    end

    it 'expõe sheet_known_spell_id e known_source grimoire para cópias no grimório' do
      sheet = create(:sheet)
      sk = create(:sheet_klass, sheet: sheet)
      sp = create(:spell, level: 2, name: 'Spec Grimo Spell', api_index: "grimo_#{SecureRandom.hex(3)}")
      ks = create(:sheet_known_spell, sheet_klass: sk, spell: sp, source: 'grimoire')

      result = described_class.new(sheet).call
      row = result[:known_by_level][2].find { |e| e[:id] == sp.id }
      expect(row[:known_source]).to eq('grimoire')
      expect(row[:sheet_known_spell_id]).to eq(ks.id)
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

    it 'conjurador known com spell_selections mantém SheetKnownSpell de raça (ex.: tiefling + bruxo)' do
      warlock = create(:klass, api_index: 'warlock', name: 'Bruxo Spec Merge')
      sp_class = create(:spell, level: 0, name: 'Eldritch Merge Spec', api_index: "kmerge_eld_#{SecureRandom.hex(3)}")
      sp_race = create(:spell, level: 0, name: 'Taumaturgia Merge Spec', api_index: "kmerge_th_#{SecureRandom.hex(3)}")
      sheet = create(:sheet, metadata: {
        'spell_selections' => {
          'cantrips' => [sp_class.id.to_s],
          'known' => [],
          'spellbook' => [],
          'prepared' => []
        }
      })
      sk = create(:sheet_klass, sheet: sheet, klass: warlock, level: 5)
      create(:sheet_known_spell, sheet_klass: sk, spell: sp_race, source: 'race')

      result = described_class.new(sheet.reload).call
      ids = result[:known_by_level].values.flatten.map { |e| e[:id] }.compact.sort
      expect(ids).to eq([sp_class.id, sp_race.id].sort)
      race_row = result[:known_by_level].values.flatten.find { |e| e[:id] == sp_race.id }
      expect(race_row[:known_source]).to eq('race')
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

    it 'inclui Arcano Místico (spell id só em metadata) em catalog_by_id sem SheetKnownSpell' do
      warlock = create(:klass, api_index: 'warlock', name: 'Bruxo Arcanum Spec')
      sp_ma = create(:spell, level: 6, name: 'Sugestão em Massa Spec', api_index: "ma_#{SecureRandom.hex(3)}")
      sheet = create(:sheet, metadata: {
        'spell_selections' => {
          'cantrips' => [],
          'known' => [],
          'spellbook' => [],
          'prepared' => []
        },
        'class_choices' => {
          'per_level' => {
            '11' => { 'mystic_arcanum_6' => [sp_ma.id] }
          }
        }
      })
      create(:sheet_klass, sheet: sheet, klass: warlock, level: 11)

      result = described_class.new(sheet.reload).call
      expect(result[:catalog_by_id][sp_ma.id]).to include(name: 'Sugestão em Massa Spec', id: sp_ma.id)
    end
  end
end
