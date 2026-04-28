# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CharacterProvisioningService, type: :service do
  describe '#reset_current_class_spell_state!' do
    let(:user) { create(:user) }
    let(:service) { described_class.new(user: user, payload: {}) }
    let(:character) { create(:character, user: user, status: :active) }
    let(:sheet) { create(:sheet, character: character) }
    let(:klass) { create(:klass) }
    let(:sheet_klass) { create(:sheet_klass, sheet: sheet, klass: klass, level: 4) }

    it 'remove rows de magia da classe (inclui source nil legado) e preserva feat/race' do
      keep_feat = create(:spell)
      keep_race = create(:spell)
      drop_nil = create(:spell)
      drop_class = create(:spell)
      drop_subclass = create(:spell)

      create(:sheet_known_spell, sheet_klass: sheet_klass, spell: keep_feat, source: 'feat')
      create(:sheet_known_spell, sheet_klass: sheet_klass, spell: keep_race, source: 'race')
      create(:sheet_known_spell, sheet_klass: sheet_klass, spell: drop_nil, source: nil)
      create(:sheet_known_spell, sheet_klass: sheet_klass, spell: drop_class, source: 'class')
      create(:sheet_known_spell, sheet_klass: sheet_klass, spell: drop_subclass, source: 'subclass')

      prep_keep_feat = create(:spell)
      prep_keep_race = create(:spell)
      prep_drop_nil = create(:spell)
      prep_drop_class = create(:spell)
      prep_drop_subclass = create(:spell)

      SheetPreparedSpell.create!(sheet_id: sheet.id, spell_id: prep_keep_feat.id, source: 'feat', auto: false)
      SheetPreparedSpell.create!(sheet_id: sheet.id, spell_id: prep_keep_race.id, source: 'race', auto: true)
      SheetPreparedSpell.create!(sheet_id: sheet.id, spell_id: prep_drop_nil.id, source: nil, auto: false)
      SheetPreparedSpell.create!(sheet_id: sheet.id, spell_id: prep_drop_class.id, source: 'class', auto: false)
      SheetPreparedSpell.create!(sheet_id: sheet.id, spell_id: prep_drop_subclass.id, source: 'subclass', auto: true)

      service.send(:reset_current_class_spell_state!, sheet: sheet, klass_id: klass.id)

      known_sources = SheetKnownSpell.where(sheet_klass_id: sheet_klass.id).pluck(:source).sort
      expect(known_sources).to eq(%w[feat race])

      prep_sources = SheetPreparedSpell.where(sheet_id: sheet.id).pluck(:source).sort
      expect(prep_sources).to eq(%w[feat race])
    end

    it 'não limpa quando a ficha é multiclasse (evita apagar prepared de outra classe)' do
      other_klass = create(:klass)
      other_sk = create(:sheet_klass, sheet: sheet, klass: other_klass, level: 2)
      spell_a = create(:spell)
      spell_b = create(:spell)

      create(:sheet_known_spell, sheet_klass: sheet_klass, spell: spell_a, source: 'class')
      create(:sheet_known_spell, sheet_klass: other_sk, spell: spell_b, source: 'class')
      SheetPreparedSpell.create!(sheet_id: sheet.id, spell_id: spell_a.id, source: 'class', auto: false)

      service.send(:reset_current_class_spell_state!, sheet: sheet, klass_id: klass.id)

      expect(SheetKnownSpell.where(sheet_klass_id: sheet_klass.id).count).to eq(1)
      expect(SheetKnownSpell.where(sheet_klass_id: other_sk.id).count).to eq(1)
      expect(SheetPreparedSpell.where(sheet_id: sheet.id).count).to eq(1)
    end
  end
end
