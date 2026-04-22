# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SheetRuntimeState, type: :model do
  let(:sheet) { create(:sheet) }

  describe 'defaults via Sheet#runtime!' do
    it 'cria runtime_state com defaults seguros' do
      runtime = sheet.runtime!
      expect(runtime).to be_persisted
      expect(runtime.death_saves).to eq('successes' => 0, 'failures' => 0, 'stable' => false)
      expect(runtime.hit_dice_used).to eq({})
      expect(runtime.exhaustion).to eq(0)
      expect(runtime.conditions).to eq([])
      expect(runtime.spell_slots_used).to eq({})
      expect(runtime.class_resources_used).to eq({})
    end

    it 'eh idempotente — chamadas repetidas retornam a mesma row' do
      r1 = sheet.runtime!
      r2 = sheet.runtime!
      expect(r1.id).to eq(r2.id)
      expect(SheetRuntimeState.where(sheet_id: sheet.id).count).to eq(1)
    end
  end

  describe 'validations' do
    let(:runtime) { sheet.runtime! }

    it 'invalida se mais de uma row para a mesma sheet' do
      runtime
      dup = SheetRuntimeState.new(sheet_id: sheet.id)
      expect(dup).not_to be_valid
      expect(dup.errors[:sheet_id]).to be_present
    end

    it 'invalida exhaustion fora de 0..6' do
      runtime.exhaustion = 7
      expect(runtime).not_to be_valid
      runtime.exhaustion = -1
      expect(runtime).not_to be_valid
      runtime.exhaustion = 6
      expect(runtime).to be_valid
    end

    it 'normaliza death_saves para o intervalo 0..3 (clamping safe-by-construction)' do
      runtime.death_saves = { 'successes' => 4, 'failures' => -1, 'stable' => false }
      expect(runtime).to be_valid
      runtime.save!
      expect(runtime.reload.death_saves).to eq('successes' => 3, 'failures' => 0, 'stable' => false)
    end
  end

  describe '#apply_patch!' do
    let(:runtime) { sheet.runtime! }

    it 'aplica patch parcial em death_saves' do
      runtime.apply_patch!(death_saves: { successes: 2, failures: 1, stable: false })
      expect(runtime.death_saves).to eq('successes' => 2, 'failures' => 1, 'stable' => false)
    end

    it 'merge em hit_dice_used (preserva chaves não enviadas)' do
      runtime.update!(hit_dice_used: { 'd10' => 2 })
      runtime.apply_patch!(hit_dice_used: { 'd8' => 1 })
      expect(runtime.hit_dice_used).to eq('d10' => 2, 'd8' => 1)
    end

    it 'merge em spell_slots_used' do
      runtime.update!(spell_slots_used: { '1' => 2 })
      runtime.apply_patch!(spell_slots_used: { '2' => 1 })
      expect(runtime.spell_slots_used).to eq('1' => 2, '2' => 1)
    end

    it 'merge em class_resources_used' do
      runtime.update!(class_resources_used: { 'rage' => 1 })
      runtime.apply_patch!(class_resources_used: { 'ki' => 3 })
      expect(runtime.class_resources_used).to eq('rage' => 1, 'ki' => 3)
    end

    it 'substitui exhaustion (escalar)' do
      runtime.apply_patch!(exhaustion: 2)
      expect(runtime.exhaustion).to eq(2)
    end

    it 'substitui conditions inteiro (não merge)' do
      runtime.update!(conditions: %w[fadigado])
      runtime.apply_patch!(conditions: %w[amedrontado envenenado])
      expect(runtime.conditions).to eq(%w[amedrontado envenenado])
    end
  end

  describe '#as_payload' do
    it 'devolve forma canônica com todas as chaves' do
      runtime = sheet.runtime!
      payload = runtime.as_payload
      expect(payload.keys).to contain_exactly(
        :death_saves, :hit_dice_used, :exhaustion, :conditions,
        :concentration, :spell_slots_used, :class_resources_used,
        :last_short_rest_at, :last_long_rest_at, :updated_at
      )
    end
  end

  describe 'Sheet destruction' do
    it 'destrói runtime_state quando sheet destruída (dependent: :destroy)' do
      runtime = sheet.runtime!
      expect { sheet.destroy }.to change(SheetRuntimeState, :count).by(-1)
    end
  end
end
