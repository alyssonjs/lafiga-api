# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sheets::Runtime::ApplyShortRestService do
  let(:sheet) { create(:sheet) }

  it 'cria runtime_state se ainda não existir' do
    expect(sheet.runtime_state).to be_nil
    described_class.call(sheet)
    sheet.reload
    expect(sheet.runtime_state).to be_present
  end

  it 'zera death_saves' do
    runtime = sheet.runtime!
    runtime.update!(death_saves: { 'successes' => 2, 'failures' => 1, 'stable' => false })
    described_class.call(sheet)
    expect(sheet.runtime_state.reload.death_saves).to eq(SheetRuntimeState::DEATH_SAVES_DEFAULT)
  end

  it 'marca timestamp last_short_rest_at' do
    now = Time.zone.local(2026, 4, 18, 12, 0, 0)
    described_class.call(sheet, now: now)
    expect(sheet.runtime_state.reload.last_short_rest_at).to be_within(1.second).of(now)
  end

  it 'NÃO toca em hit_dice_used (Fase A: descanso curto não recupera dados de vida)' do
    runtime = sheet.runtime!
    runtime.update!(hit_dice_used: { 'd10' => 2 })
    described_class.call(sheet)
    expect(sheet.runtime_state.reload.hit_dice_used).to eq('d10' => 2)
  end

  it 'NÃO toca em exhaustion (descanso curto não reduz)' do
    runtime = sheet.runtime!
    runtime.update!(exhaustion: 2)
    described_class.call(sheet)
    expect(sheet.runtime_state.reload.exhaustion).to eq(2)
  end

  describe 'Fase B: spell slots' do
    it 'reseta apenas pact slots (Bruxo) e mantem demais slots consumidos' do
      runtime = sheet.runtime!
      runtime.update!(spell_slots_used: { '1' => 2, '2' => 1, 'pact' => 1 })
      described_class.call(sheet)
      expect(sheet.runtime_state.reload.spell_slots_used).to eq('1' => 2, '2' => 1)
    end

    it 'no-op em spell_slots_used sem pact' do
      runtime = sheet.runtime!
      runtime.update!(spell_slots_used: { '1' => 1 })
      described_class.call(sheet)
      expect(sheet.runtime_state.reload.spell_slots_used).to eq('1' => 1)
    end
  end

  describe 'Fase C: class_resources_used' do
    it 'zera recursos com recharge: short (ki, channel_divinity, second_wind, action_surge, wild_shape)' do
      runtime = sheet.runtime!
      runtime.update!(class_resources_used: {
        'ki' => 3, 'channel_divinity' => 1, 'second_wind' => 1,
        'action_surge' => 1, 'wild_shape' => 2
      })
      described_class.call(sheet)
      expect(sheet.runtime_state.reload.class_resources_used).to eq({})
    end

    it 'preserva recursos com recharge: long (rage, indomitable, sorcery_points, etc.)' do
      runtime = sheet.runtime!
      runtime.update!(class_resources_used: {
        'rage' => 2, 'indomitable' => 1, 'sorcery_points' => 4,
        'ki' => 1
      })
      described_class.call(sheet)
      expect(sheet.runtime_state.reload.class_resources_used).to eq(
        'rage' => 2, 'indomitable' => 1, 'sorcery_points' => 4
      )
    end

    it 'preserva chaves desconhecidas (compat com saves antigos / homebrew)' do
      runtime = sheet.runtime!
      runtime.update!(class_resources_used: { 'custom_resource' => 5, 'ki' => 2 })
      described_class.call(sheet)
      expect(sheet.runtime_state.reload.class_resources_used).to eq('custom_resource' => 5)
    end
  end

  describe 'P2.14: bardic_inspiration recharge dinamico' do
    let(:bard_klass) do
      Klass.find_or_create_by!(api_index: 'bard') { |k| k.name = 'Bardo'; k.hit_die = 8; k.subclass_level = 3 }
    end

    def bard_sheet_at(level)
      s = create(:sheet, current_level: level)
      SheetKlass.create!(sheet: s, klass: bard_klass, level: level)
      s
    end

    it 'NAO zera bardic_inspiration em SR antes do nivel 5 (LR padrao)' do
      s = bard_sheet_at(4)
      s.runtime!.update!(class_resources_used: { 'bardic_inspiration' => 2 })
      described_class.call(s)
      expect(s.runtime_state.reload.class_resources_used).to eq('bardic_inspiration' => 2)
    end

    it 'zera bardic_inspiration em SR a partir do nivel 5 (Font of Inspiration)' do
      s = bard_sheet_at(5)
      s.runtime!.update!(class_resources_used: { 'bardic_inspiration' => 3, 'rage' => 1 })
      described_class.call(s)
      expect(s.runtime_state.reload.class_resources_used).to eq('rage' => 1)
    end

    it 'continua zerando em SR em niveis altos (10, 15, 20)' do
      [10, 15, 20].each do |lvl|
        s = bard_sheet_at(lvl)
        s.runtime!.update!(class_resources_used: { 'bardic_inspiration' => 5 })
        described_class.call(s)
        expect(s.runtime_state.reload.class_resources_used).to eq({}), "nv #{lvl}"
      end
    end
  end
end
