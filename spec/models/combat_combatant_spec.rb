require 'rails_helper'

RSpec.describe CombatCombatant, type: :model do
  let(:schedule)     { create(:schedule) }
  let(:combat_state) { create(:combat_state, schedule: schedule) }
  let(:character)    { create(:character, group: schedule.group) }

  describe 'polymorphic combatable' do
    it 'accepts a Character as combatable (PC)' do
      c = create(:combat_combatant, combat_state: combat_state, combatable: character, position: 0)
      expect(c.combatable).to eq(character)
      expect(c.combatable_type).to eq('Character')
    end

    it 'accepts a CombatNpc as combatable (NPC)' do
      npc = create(:combat_npc, schedule: schedule)
      c = create(:combat_combatant, :npc, combat_state: combat_state, combatable: npc, position: 0)
      expect(c.combatable).to eq(npc)
      expect(c.combatable_type).to eq('CombatNpc')
    end

    it 'enforces unique position within the same combat_state' do
      create(:combat_combatant, combat_state: combat_state, combatable: character, position: 0)
      dup = build(:combat_combatant, combat_state: combat_state, combatable: create(:character, group: schedule.group), position: 0)
      expect { dup.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'G13 — combatable_belongs_to_session validation' do
    it 'rejects a Character from a different group' do
      other_group = create(:group)
      foreign_character = create(:character, group: other_group)
      bad = build(:combat_combatant, combat_state: combat_state, combatable: foreign_character, position: 0)
      expect(bad).not_to be_valid
      expect(bad.errors[:combatable]).to include('pertence a outro grupo')
    end

    it 'accepts a Character with no group set (e.g. unassigned PC) without raising' do
      char_without_group = create(:character, group: nil)
      ok = build(:combat_combatant, combat_state: combat_state, combatable: char_without_group, position: 0)
      expect(ok).to be_valid
    end

    it 'rejects a CombatNpc from a different schedule' do
      other_schedule = create(:schedule)
      foreign_npc = create(:combat_npc, schedule: other_schedule)
      bad = build(:combat_combatant, :npc, combat_state: combat_state, combatable: foreign_npc, position: 0)
      expect(bad).not_to be_valid
      expect(bad.errors[:combatable]).to include('pertence a outra sessão')
    end
  end

  describe 'JSONB defaults' do
    it 'fills conditions/actions_used/death_saves with valid defaults' do
      c = create(:combat_combatant, combat_state: combat_state, combatable: character, position: 0)
      expect(c.conditions).to eq([])
      expect(c.actions_used).to include('action' => false, 'bonus_action' => false, 'movement' => false, 'reaction' => false)
      expect(c.death_saves).to include('successes' => 0, 'failures' => 0)
    end
  end

  describe '#tick_conditions_at_end_of_turn!' do
    let(:c) { create(:combat_combatant, combat_state: combat_state, combatable: character, position: 0) }

    it 'decrementa turns_left > 1' do
      c.update!(conditions: [{ 'id' => 'poisoned', 'turns_left' => 3 }])
      expect(c.tick_conditions_at_end_of_turn!).to be true
      expect(c.reload.conditions).to eq([{ 'id' => 'poisoned', 'turns_left' => 2 }])
    end

    it 'remove quando turns_left == 1' do
      c.update!(conditions: [{ 'id' => 'poisoned', 'turns_left' => 1 }])
      expect(c.tick_conditions_at_end_of_turn!).to be true
      expect(c.reload.conditions).to eq([])
    end

    it 'mantem indefinido quando turns_left ausente ou 0' do
      c.update!(conditions: [
        { 'id' => 'grappled' },
        { 'id' => 'restrained', 'turns_left' => 0 },
      ])
      expect(c.tick_conditions_at_end_of_turn!).to be false
      expect(c.reload.conditions.map(&:stringify_keys)).to match_array([
        { 'id' => 'grappled' },
        { 'id' => 'restrained', 'turns_left' => 0 },
      ])
    end
  end

  describe 'JSONB validations' do
    let(:base) { build(:combat_combatant, combat_state: combat_state, combatable: character, position: 0) }

    it 'rejects malformed conditions (missing id)' do
      base.conditions = [{ 'turns_left' => 3 }]
      expect(base).not_to be_valid
      expect(base.errors[:conditions]).to be_present
    end

    it 'rejects death_saves out of range' do
      base.death_saves = { 'successes' => 4, 'failures' => 0 }
      expect(base).not_to be_valid
      expect(base.errors[:death_saves]).to be_present
    end

    it 'rejects actions_used missing keys' do
      base.actions_used = { 'action' => true } # missing bonus_action, movement, reaction
      expect(base).not_to be_valid
      expect(base.errors[:actions_used]).to be_present
    end
  end

  describe '#apply_damage!' do
    let(:c) { create(:combat_combatant, combat_state: combat_state, combatable: character, position: 0, hp_current: 20, hp_max: 20, temp_hp: 5) }

    it 'consumes temp_hp before hp_current' do
      c.apply_damage!(3)
      expect(c.reload).to have_attributes(temp_hp: 2, hp_current: 20)
    end

    it 'overflows from temp_hp to hp_current' do
      c.apply_damage!(8)
      expect(c.reload).to have_attributes(temp_hp: 0, hp_current: 17)
    end

    it 'floors hp_current at 0 (PC stays alive — death saves)' do
      c.apply_damage!(100)
      expect(c.reload).to have_attributes(hp_current: 0, is_dead: false)
    end

    it 'marks NPC as dead at 0 HP' do
      npc = create(:combat_npc, schedule: schedule)
      c2 = create(:combat_combatant, :npc, combat_state: combat_state, combatable: npc, position: 1, hp_current: 5, hp_max: 5)
      c2.apply_damage!(100)
      expect(c2.reload).to have_attributes(hp_current: 0, is_dead: true)
    end

    it 'rejects negative damage' do
      expect { c.apply_damage!(-1) }.to raise_error(ArgumentError)
    end
  end

  describe '#heal!' do
    let(:c) { create(:combat_combatant, combat_state: combat_state, combatable: character, position: 0, hp_current: 5, hp_max: 20, is_stabilized: true) }

    it 'caps at hp_max' do
      c.heal!(100)
      expect(c.reload.hp_current).to eq(20)
    end

    it 'unstabilizes when healed above 0' do
      c.update!(hp_current: 0, is_stabilized: true, is_dead: true)
      c.heal!(3)
      expect(c.reload).to have_attributes(hp_current: 3, is_stabilized: false, is_dead: false)
    end
  end

  describe '#reset_turn_actions!' do
    it 'resets all action flags to false' do
      c = create(:combat_combatant, combat_state: combat_state, combatable: character, position: 0,
                 actions_used: { 'action' => true, 'bonus_action' => true, 'movement' => true, 'reaction' => false })
      c.reset_turn_actions!
      expect(c.reload.actions_used).to include('action' => false, 'bonus_action' => false, 'movement' => false, 'reaction' => false)
    end
  end

  describe 'G15 — auto_resolve_death_saves' do
    let(:c) { create(:combat_combatant, combat_state: combat_state, combatable: character, position: 0, hp_current: 0) }

    it 'marks is_stabilized=true and zeroes counters when successes hit 3' do
      c.update!(death_saves: { 'successes' => 3, 'failures' => 1 })
      expect(c.reload).to have_attributes(is_stabilized: true)
      expect(c.death_saves).to include('successes' => 0, 'failures' => 0)
    end

    it 'marks is_dead=true and zeroes counters when failures hit 3' do
      c.update!(death_saves: { 'successes' => 1, 'failures' => 3 })
      expect(c.reload).to have_attributes(is_dead: true)
      expect(c.death_saves).to include('successes' => 0, 'failures' => 0)
    end

    it 'leaves flags untouched when below thresholds' do
      c.update!(death_saves: { 'successes' => 2, 'failures' => 2 })
      expect(c.reload).to have_attributes(is_dead: false, is_stabilized: false)
      expect(c.death_saves).to include('successes' => 2, 'failures' => 2)
    end
  end

  describe '#record_death_save!' do
    let(:c) { create(:combat_combatant, combat_state: combat_state, combatable: character, position: 0, hp_current: 0) }

    it 'increments successes and stabilizes on the third' do
      2.times { c.record_death_save!(:success) }
      expect(c.reload).to have_attributes(is_stabilized: false)
      c.record_death_save!(:success)
      expect(c.reload).to have_attributes(is_stabilized: true)
    end

    it 'increments failures and kills on the third' do
      2.times { c.record_death_save!(:failure) }
      expect(c.reload).to have_attributes(is_dead: false)
      c.record_death_save!(:failure)
      expect(c.reload).to have_attributes(is_dead: true)
    end

    it 'rejects unknown kinds' do
      expect { c.record_death_save!(:critical) }.to raise_error(ArgumentError)
    end
  end

  describe 'G8 — sync_npc_defeated_state' do
    let(:npc) { create(:combat_npc, schedule: schedule) }
    let(:c)   { create(:combat_combatant, :npc, combat_state: combat_state, combatable: npc, position: 0, hp_current: 5, hp_max: 5) }

    it 'sets defeated_at on the NPC when combatant becomes is_dead' do
      c.apply_damage!(100)  # zera HP, marca is_dead (NPC), trigger sync
      expect(npc.reload.alive?).to be false
      expect(npc.defeated_at).to be_present
    end

    it 'reverses defeated_at when an NPC combatant is healed back above 0' do
      c.apply_damage!(100)
      expect(npc.reload.alive?).to be false

      # Manualmente "ressuscita" (cura): is_dead vira false e HP > 0
      c.update!(is_dead: false)
      c.heal!(3)

      expect(npc.reload.alive?).to be true
    end

    it 'does NOT touch any NPC for PC combatants' do
      pc = create(:combat_combatant, combat_state: combat_state, combatable: character, position: 1, hp_current: 0)
      pc.update!(death_saves: { 'successes' => 0, 'failures' => 3 })
      expect(pc.reload.is_dead).to be true
      # nada para sincronizar — Character não tem defeated_at
      expect { pc.save! }.not_to raise_error
    end
  end
end
