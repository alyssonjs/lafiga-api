require 'rails_helper'

RSpec.describe CombatState, type: :model do
  let(:schedule) { create(:schedule) }

  describe 'validations' do
    it 'requires a schedule' do
      cs = CombatState.new
      expect(cs).not_to be_valid
      expect(cs.errors[:schedule]).to be_present
    end

    it 'allows only one combat_state per schedule (unique index)' do
      create(:combat_state, schedule: schedule)
      dup = build(:combat_state, schedule: schedule)
      expect { dup.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'requires round >= 1 when active' do
      cs = build(:combat_state, schedule: schedule, active: true, round: 0)
      expect(cs).not_to be_valid
      expect(cs.errors[:round]).to be_present
    end
  end

  describe '#begin!' do
    it 'activates and sets round to 1 from a fresh state' do
      cs = create(:combat_state, schedule: schedule)
      cs.begin!
      expect(cs.reload).to have_attributes(active: true, round: 1, current_turn_index: 0)
      expect(cs.started_at).to be_present
      expect(cs.ended_at).to be_nil
    end

    it 'is idempotent when already active' do
      cs = create(:combat_state, schedule: schedule, active: true, round: 3, current_turn_index: 2)
      original_started_at = (cs.started_at = 1.hour.ago)
      cs.save!
      cs.begin!
      expect(cs.reload).to have_attributes(active: true, round: 3, current_turn_index: 2)
      expect(cs.started_at).to be_within(1.second).of(original_started_at)
    end

    it 'restarts after finish! resetting current_turn_index but keeping started_at' do
      cs = create(:combat_state, schedule: schedule, active: true, round: 5, current_turn_index: 3, started_at: 2.hours.ago)
      cs.finish!
      cs.begin!
      expect(cs.reload).to have_attributes(active: true, round: 5, current_turn_index: 0, ended_at: nil)
    end
  end

  describe '#finish!' do
    it 'deactivates and stamps ended_at' do
      cs = create(:combat_state, schedule: schedule, active: true, round: 2, started_at: 1.hour.ago)
      cs.finish!
      expect(cs.reload.active).to be false
      expect(cs.ended_at).to be_present
    end

    it 'is a no-op when already inactive' do
      cs = create(:combat_state, schedule: schedule, active: false)
      expect { cs.finish! }.not_to change { cs.reload.updated_at }
    end
  end

  describe '#advance_turn!' do
    let(:cs) { create(:combat_state, schedule: schedule, active: true, round: 1, current_turn_index: 0) }
    let(:character) { create(:character, group: schedule.group) }

    before do
      create(:combat_combatant, combat_state: cs, combatable: character, position: 0)
      npc = create(:combat_npc, schedule: schedule)
      create(:combat_combatant, :npc, combat_state: cs, combatable: npc, position: 1)
    end

    it 'advances to the next combatant within the same round' do
      cs.advance_turn!
      expect(cs.reload).to have_attributes(round: 1, current_turn_index: 1)
    end

    it 'rolls over to round+1 and back to first living combatant after the last' do
      cs.update!(current_turn_index: 1)
      cs.advance_turn!
      expect(cs.reload).to have_attributes(round: 2, current_turn_index: 0)
    end

    it 'is a no-op when combat is inactive' do
      cs.update!(active: false)
      expect { cs.advance_turn! }.not_to change { cs.reload.current_turn_index }
    end

    it 'is a no-op when there are no living combatants' do
      cs.combat_combatants.update_all(is_dead: true)
      expect { cs.advance_turn! }.not_to change { cs.reload.current_turn_index }
    end

    # G4 — pula combatentes mortos
    it 'skips dead combatants when advancing within the same round' do
      char2 = create(:character, group: schedule.group)
      create(:combat_combatant, combat_state: cs, combatable: char2, position: 2)

      cs.combat_combatants.find_by(position: 1).update!(is_dead: true)
      cs.advance_turn!  # 0 -> deveria pular pos 1 (morto) e ir para pos 2
      expect(cs.reload.current_turn_index).to eq(2)
    end

    it 'rolls over correctly when only the first position is alive (skips dead tail)' do
      cs.combat_combatants.find_by(position: 1).update!(is_dead: true)
      cs.update!(current_turn_index: 0)
      cs.advance_turn!  # único vivo é pos 0; deveria voltar para 0 e round+1
      expect(cs.reload).to have_attributes(round: 2, current_turn_index: 0)
    end

    # G7 — reseta actions_used do novo combatente ativo
    it 'resets actions_used of the combatant who just got the turn' do
      next_combatant = cs.combat_combatants.find_by(position: 1)
      next_combatant.update!(actions_used: { 'action' => true, 'bonus_action' => true, 'movement' => true, 'reaction' => false })

      cs.advance_turn!  # 0 -> 1, deveria resetar actions de pos 1
      expect(next_combatant.reload.actions_used).to include(
        'action' => false, 'bonus_action' => false, 'movement' => false, 'reaction' => false
      )
    end

    it 'nao decrementa turns_left no meio da rodada (só ao fechar o ciclo da iniciativa)' do
      pc = cs.combat_combatants.find_by(position: 0)
      npc = cs.combat_combatants.find_by(position: 1)
      pc.update!(conditions: [{ 'id' => 'paralyzed', 'turns_left' => 5 }])
      npc.update!(conditions: [{ 'id' => 'poisoned', 'turns_left' => 3 }])

      cs.advance_turn! # 0 -> 1, mesma rodada
      expect(pc.reload.conditions).to eq([{ 'id' => 'paralyzed', 'turns_left' => 5 }])
      expect(npc.reload.conditions).to eq([{ 'id' => 'poisoned', 'turns_left' => 3 }])
    end

    it 'decrementa turns_left em todos os vivos ao fim da rodada (volta ao primeiro)' do
      pc = cs.combat_combatants.find_by(position: 0)
      npc = cs.combat_combatants.find_by(position: 1)
      pc.update!(conditions: [
        { 'id' => 'paralyzed', 'turns_left' => 5 },
        { 'id' => 'grappled', 'turns_left' => 0 },
      ])
      npc.update!(conditions: [{ 'id' => 'poisoned', 'turns_left' => 2 }])

      cs.update!(current_turn_index: 1)
      cs.advance_turn! # último passa -> rodada 2, índice 0
      expect(cs.reload.round).to eq(2)
      pc.reload
      npc.reload
      expect(pc.conditions).to match_array([
        hash_including('id' => 'paralyzed', 'turns_left' => 4),
        hash_including('id' => 'grappled', 'turns_left' => 0),
      ])
      expect(npc.conditions).to eq([{ 'id' => 'poisoned', 'turns_left' => 1 }])
    end

    it 'remove condicao quando turns_left chega a 1 ao fim da rodada' do
      pc = cs.combat_combatants.find_by(position: 0)
      npc = cs.combat_combatants.find_by(position: 1)
      pc.update!(conditions: [{ 'id' => 'blinded', 'turns_left' => 1 }])
      npc.update!(conditions: [{ 'id' => 'deafened', 'turns_left' => 5 }])

      cs.update!(current_turn_index: 1)
      cs.advance_turn!
      expect(pc.reload.conditions).to eq([])
      expect(npc.reload.conditions).to eq([{ 'id' => 'deafened', 'turns_left' => 4 }])
    end
  end
end
