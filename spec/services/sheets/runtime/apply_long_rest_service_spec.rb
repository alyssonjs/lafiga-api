# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sheets::Runtime::ApplyLongRestService do
  let(:sheet) { create(:sheet, current_level: 6) }
  # SheetKlass para somar level: factory base não cria; alguns specs precisam.
  # Para Fase A o test usa override de hit_dice_used direto.

  it 'cria runtime_state se não existir' do
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

  it 'reduz exhaustion em 1 (mínimo 0)' do
    runtime = sheet.runtime!
    runtime.update!(exhaustion: 3)
    described_class.call(sheet)
    expect(sheet.runtime_state.reload.exhaustion).to eq(2)
  end

  it 'mantém exhaustion em 0 quando já era 0 (não vai negativo)' do
    runtime = sheet.runtime!
    runtime.update!(exhaustion: 0)
    described_class.call(sheet)
    expect(sheet.runtime_state.reload.exhaustion).to eq(0)
  end

  it 'recupera floor(level/2) hit_dice_used (mínimo 1) — drena dos mais usados' do
    create(:sheet_klass, sheet: sheet, level: 6)
    runtime = sheet.runtime!
    runtime.update!(hit_dice_used: { 'd10' => 4, 'd8' => 1 })
    described_class.call(sheet)
    # Level total 6 → recupera 3. Drena 3 do d10 (mais usado).
    expect(sheet.runtime_state.reload.hit_dice_used).to eq('d10' => 1, 'd8' => 1)
  end

  it 'no-op em hit_dice_used se nada foi usado' do
    runtime = sheet.runtime!
    runtime.update!(hit_dice_used: {})
    described_class.call(sheet)
    expect(sheet.runtime_state.reload.hit_dice_used).to eq({})
  end

  it 'marca timestamp last_long_rest_at' do
    now = Time.zone.local(2026, 4, 18, 12, 0, 0)
    described_class.call(sheet, now: now)
    expect(sheet.runtime_state.reload.last_long_rest_at).to be_within(1.second).of(now)
  end

  describe 'Fase B: spell slots' do
    it 'zera spell_slots_used inteiro (incluindo pact)' do
      runtime = sheet.runtime!
      runtime.update!(spell_slots_used: { '1' => 2, '2' => 1, '3' => 1, 'pact' => 1 })
      described_class.call(sheet)
      expect(sheet.runtime_state.reload.spell_slots_used).to eq({})
    end

    it 'no-op quando ja zerado' do
      runtime = sheet.runtime!
      runtime.update!(spell_slots_used: {})
      described_class.call(sheet)
      expect(sheet.runtime_state.reload.spell_slots_used).to eq({})
    end
  end

  describe 'Fase C: class_resources_used' do
    it 'zera TODOS os recursos conhecidos (regra: tudo SR tambem LR)' do
      runtime = sheet.runtime!
      runtime.update!(class_resources_used: {
        'rage' => 2, 'ki' => 3, 'channel_divinity' => 1, 'sorcery_points' => 4
      })
      described_class.call(sheet)
      expect(sheet.runtime_state.reload.class_resources_used).to eq({})
    end

    it 'preserva chaves desconhecidas (homebrew / saves antigos)' do
      runtime = sheet.runtime!
      runtime.update!(class_resources_used: { 'custom_xyz' => 1, 'rage' => 2 })
      described_class.call(sheet)
      expect(sheet.runtime_state.reload.class_resources_used).to eq('custom_xyz' => 1)
    end
  end
end
