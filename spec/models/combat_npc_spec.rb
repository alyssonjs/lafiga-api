require 'rails_helper'

RSpec.describe CombatNpc, type: :model do
  let(:schedule) { create(:schedule) }

  describe 'validations' do
    it 'requires name and schedule' do
      npc = CombatNpc.new
      expect(npc).not_to be_valid
      expect(npc.errors[:name]).to be_present
      expect(npc.errors[:schedule]).to be_present
    end

    it 'rejects negative HP' do
      npc = build(:combat_npc, schedule: schedule, hp_current: -1)
      expect(npc).not_to be_valid
    end

    it 'rejects unknown stat keys' do
      npc = build(:combat_npc, schedule: schedule, stats: { 'foo' => 1 })
      expect(npc).not_to be_valid
      expect(npc.errors[:stats]).to be_present
    end

    it 'accepts known stat keys' do
      npc = build(:combat_npc, schedule: schedule, stats: { 'str' => 12, 'dex' => 14 })
      expect(npc).to be_valid
    end
  end

  describe 'scopes' do
    it 'separates alive from defeated' do
      alive = create(:combat_npc, schedule: schedule)
      dead  = create(:combat_npc, schedule: schedule, defeated_at: 1.minute.ago)
      expect(CombatNpc.alive).to include(alive)
      expect(CombatNpc.alive).not_to include(dead)
      expect(CombatNpc.defeated).to include(dead)
    end
  end

  describe '#defeat! / #revive!' do
    it 'marks defeated_at and reverses' do
      npc = create(:combat_npc, schedule: schedule)
      npc.defeat!
      expect(npc.alive?).to be false
      npc.revive!
      expect(npc.alive?).to be true
    end

    it 'defeat! is idempotent' do
      npc = create(:combat_npc, schedule: schedule, defeated_at: 1.minute.ago)
      expect { npc.defeat! }.not_to change { npc.reload.defeated_at }
    end
  end
end
