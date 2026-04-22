require 'rails_helper'

RSpec.describe Combat::EndService, type: :service do
  let(:schedule)  { create(:schedule) }
  let(:user)      { create(:user) }
  let(:character) { create(:character, user: user, group: schedule.group) }

  describe '#call' do
    it 'finishes the active combat and stamps ended_at' do
      cs = create(:combat_state, schedule: schedule, active: true, round: 3, started_at: 1.hour.ago)
      result = described_class.call(schedule: schedule)
      expect(result).to be_success
      expect(cs.reload).to have_attributes(active: false)
      expect(cs.ended_at).to be_present
    end

    it 'syncs combatant HP back into the PC Sheet (G27)' do
      sheet = create(:sheet, character: character, hp_current: 25, hp_max: 25, temp_hp: 0)
      cs = create(:combat_state, schedule: schedule, active: true, round: 1, started_at: 1.minute.ago)
      create(:combat_combatant, combat_state: cs, combatable: character, position: 0,
             hp_current: 9, hp_max: 25, temp_hp: 3)

      described_class.call(schedule: schedule)

      expect(sheet.reload).to have_attributes(hp_current: 9, temp_hp: 3, hp_max: 25)
    end

    it 'does not change Sheet hp_max even if combatant hp_max diverged mid-combat' do
      sheet = create(:sheet, character: character, hp_current: 25, hp_max: 25)
      cs = create(:combat_state, schedule: schedule, active: true, round: 1, started_at: 1.minute.ago)
      create(:combat_combatant, combat_state: cs, combatable: character, position: 0,
             hp_current: 12, hp_max: 50)  # buffed mid-combat via spell

      described_class.call(schedule: schedule)

      expect(sheet.reload).to have_attributes(hp_current: 12, hp_max: 25)
    end

    it 'returns error when there is no combat_state for the schedule' do
      result = described_class.call(schedule: schedule)
      expect(result).not_to be_success
      expect(result.errors[:combat_state]).to be_present
    end

    it 'returns error when schedule is nil' do
      result = described_class.call(schedule: nil)
      expect(result).not_to be_success
      expect(result.errors[:schedule]).to be_present
    end

    it 'is a no-op finish if combat was already inactive' do
      cs = create(:combat_state, schedule: schedule, active: false, ended_at: 2.hours.ago)
      original_ended_at = cs.ended_at
      described_class.call(schedule: schedule)
      expect(cs.reload.ended_at).to be_within(1.second).of(original_ended_at)
    end
  end
end
