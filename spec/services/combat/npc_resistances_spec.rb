# frozen_string_literal: true

require 'rails_helper'

# BDD Fase 6E — CombatNpc com resistências/imunidades/legendary/lair.
RSpec.describe 'CombatNpc — resistances + DamageService integration (Fase 6E)', type: :model do
  let(:schedule) { create(:schedule) }
  let!(:cs) { CombatState.create!(schedule: schedule, active: true, round: 1, current_turn_index: 0) }

  def make_npc(opts = {})
    CombatNpc.create!({
      schedule: schedule, name: "NPC #{SecureRandom.hex(2)}",
      hp_current: 50, hp_max: 50, ac: 14, base_ac: 14,
      stats: { 'str' => 16, 'dex' => 12, 'con' => 14, 'int' => 8, 'wis' => 10, 'cha' => 8 },
      attacks: []
    }.merge(opts))
  end

  def make_combatant(npc, hp: 50, concentrating: false)
    CombatCombatant.create!(
      combat_state: cs, combatable: npc, position: 1, name: npc.name,
      initiative: 10, initiative_bonus: 0, tie_break_dex: 12,
      hp_current: hp, hp_max: hp, ac: npc.ac, temp_hp: 0,
      is_concentrating: concentrating
    )
  end

  describe 'colunas novas (migration Fase 6E)' do
    it 'tem defaults [] em resistances/immunities/vulnerabilities/condition_immunities/legendary/lair' do
      npc = make_npc
      expect(npc.resistances).to eq([])
      expect(npc.damage_immunities).to eq([])
      expect(npc.damage_vulnerabilities).to eq([])
      expect(npc.condition_immunities).to eq([])
      expect(npc.legendary_actions).to eq([])
      expect(npc.lair_actions).to eq([])
    end

    it 'aceita arrays JSONB nos novos campos' do
      npc = make_npc(
        resistances: ['fogo', 'frio'],
        damage_immunities: ['veneno'],
        condition_immunities: ['envenenado'],
        legendary_actions: [
          { 'name' => 'Ataque com Cauda', 'cost' => 1, 'description' => '...' }
        ],
        lair_actions: [
          { 'name' => 'Tremor', 'description' => 'Conjura sismo na sala' }
        ]
      )
      expect(npc.resistances).to contain_exactly('fogo', 'frio')
      expect(npc.legendary_actions.first['name']).to eq('Ataque com Cauda')
      expect(npc.lair_actions.first['description']).to match(/sismo/i)
    end
  end

  describe 'integração com DamageService (Fase 6A + 6E)' do
    it 'NPC com resistance fogo sofre metade do dano' do
      npc = make_npc(resistances: ['fogo'])
      combatant = make_combatant(npc)

      result = Combat::DamageService.call(combatant: combatant, amount: 20, damage_type: 'fogo')
      expect(result.success?).to be(true)
      expect(result.result[:damage_modifier]).to eq(:resistant)
      expect(result.result[:damage_applied]).to eq(10)
    end

    it 'NPC com damage_immunities veneno sofre 0' do
      npc = make_npc(damage_immunities: ['veneno'])
      combatant = make_combatant(npc)

      result = Combat::DamageService.call(combatant: combatant, amount: 30, damage_type: 'veneno')
      expect(result.result[:damage_applied]).to eq(0)
      expect(result.result[:damage_modifier]).to eq(:immune)
    end

    it 'NPC com damage_vulnerabilities frio sofre 2x' do
      npc = make_npc(damage_vulnerabilities: ['frio'])
      combatant = make_combatant(npc)

      result = Combat::DamageService.call(combatant: combatant, amount: 10, damage_type: 'frio')
      expect(result.result[:damage_applied]).to eq(20)
      expect(result.result[:damage_modifier]).to eq(:vulnerable)
    end

    it 'NPC sem resistance específica sofre dano cheio' do
      npc = make_npc
      combatant = make_combatant(npc)
      result = Combat::DamageService.call(combatant: combatant, amount: 15, damage_type: 'cortante')
      expect(result.result[:damage_applied]).to eq(15)
      expect(result.result[:damage_modifier]).to eq(:normal)
    end
  end

  describe 'serializer expõe os novos campos (Fase 6E)' do
    it 'inclui resistances/immunities/legendary/lair no payload' do
      npc = make_npc(
        resistances: ['fogo'],
        legendary_actions: [{ 'name' => 'Mordida' }]
      )
      payload = ::Combat::Serializers.npc(npc)
      expect(payload[:resistances]).to eq(['fogo'])
      expect(payload[:legendary_actions]).to eq([{ 'name' => 'Mordida' }])
    end
  end
end
