require 'rails_helper'

RSpec.describe Combat::StartService, type: :service do
  let(:schedule)  { create(:schedule) }
  let(:user)      { create(:user) }
  let(:character) { create(:character, user: user, group: schedule.group) }

  describe '#call' do
    it 'creates a CombatState if missing and activates it' do
      result = described_class.call(schedule: schedule)
      expect(result).to be_success
      cs = result.result
      expect(cs).to be_a(CombatState)
      expect(cs).to have_attributes(active: true, round: 1, current_turn_index: 0)
      expect(cs.started_at).to be_present
    end

    it 'is idempotent when combat is already active' do
      cs = create(:combat_state, schedule: schedule, active: true, round: 4, current_turn_index: 2, started_at: 1.hour.ago)
      result = described_class.call(schedule: schedule)
      expect(result).to be_success
      expect(cs.reload).to have_attributes(active: true, round: 4, current_turn_index: 2)
    end

    it 'reuses CombatState after a previous finish! (restart)' do
      cs = create(:combat_state, schedule: schedule, active: false, round: 5, ended_at: 1.minute.ago)
      result = described_class.call(schedule: schedule)
      expect(cs.reload).to have_attributes(active: true, round: 5, current_turn_index: 0, ended_at: nil)
    end

    it 'syncs HP from Sheet into existing PC combatants (G27)' do
      sheet = create(:sheet, character: character, hp_current: 18, hp_max: 25, temp_hp: 4)
      cs = create(:combat_state, schedule: schedule)
      pc_combatant = create(:combat_combatant, combat_state: cs, combatable: character, position: 0,
                            hp_current: 1, hp_max: 1, temp_hp: 0)

      described_class.call(schedule: schedule)

      expect(pc_combatant.reload).to have_attributes(hp_current: 18, hp_max: 25, temp_hp: 4)
    end

    it 'leaves combatant HP untouched when the PC has no Sheet' do
      cs = create(:combat_state, schedule: schedule)
      pc_combatant = create(:combat_combatant, combat_state: cs, combatable: character, position: 0,
                            hp_current: 7, hp_max: 7)

      described_class.call(schedule: schedule)

      expect(pc_combatant.reload).to have_attributes(hp_current: 7, hp_max: 7)
    end

    it 'ignores NPC combatants in HP sync' do
      npc = create(:combat_npc, schedule: schedule, hp_current: 3, hp_max: 3)
      cs = create(:combat_state, schedule: schedule)
      npc_combatant = create(:combat_combatant, :npc, combat_state: cs, combatable: npc, position: 0,
                             hp_current: 9, hp_max: 9)

      described_class.call(schedule: schedule)

      expect(npc_combatant.reload).to have_attributes(hp_current: 9, hp_max: 9)
    end

    it 'returns errors when schedule is nil' do
      result = described_class.call(schedule: nil)
      expect(result).not_to be_success
      expect(result.errors[:schedule]).to be_present
    end
  end
end
