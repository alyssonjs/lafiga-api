# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Combat::InteractionService do
  describe '.build_contest' do
    let(:params) do
      {
        kind: 'contest',
        source_id: 'atk-1',
        target_ids: ['def-1'],
        label: 'Empurrão',
        attacker_roll: { total: 18, formula: '1d20+5', skill: 'Atletismo' },
      }
    end

    it 'monta a interação na fase roll com defensor pendente' do
      ai = described_class.build_contest(params)
      expect(ai['kind']).to eq('contest')
      expect(ai['phase']).to eq('roll')
      expect(ai['source_id']).to eq('atk-1')
      expect(ai['target_ids']).to eq(['def-1'])
      expect(ai['id']).to be_present
      expect(ai['pending_responders']).to eq([
        { 'character_id' => 'def-1', 'need' => 'roll_contest', 'owned_by_dm' => false, 'responded' => false },
      ])
      expect(ai['contest']['attacker_skill']).to eq('Atletismo')
      expect(ai['contest']['defender_skill_options']).to eq(%w[Atletismo Acrobacia])
      expect(ai['contest']['attacker_roll']).to include('total' => 18, 'formula' => '1d20+5')
      expect(ai['contest']['defender_roll']).to be_nil
      expect(ai['contest']['outcome']).to be_nil
    end

    it 'marca owned_by_dm quando o defensor é NPC' do
      ai = described_class.build_contest(params.merge(pending_defender_owned_by_dm: true))
      expect(ai['pending_responders'].first['owned_by_dm']).to be true
    end

    it 'retorna nil sem source_id' do
      expect(described_class.build_contest(params.merge(source_id: ''))).to be_nil
    end

    it 'retorna nil sem target_ids' do
      expect(described_class.build_contest(params.merge(target_ids: []))).to be_nil
    end

    it 'retorna nil para kind não suportado na Fase 1' do
      expect(described_class.build_contest(params.merge(kind: 'attack'))).to be_nil
    end
  end

  describe '.apply_response' do
    let(:current) { described_class.build_contest(kind: 'contest', source_id: 'atk-1', target_ids: ['def-1'], attacker_roll: { total: 18 }) }

    it 'aplica defender_roll, resolve e avança para hit_determined' do
      next_ai, err = described_class.apply_response(current, { character_id: 'def-1', defender_roll: { total: 14, skill: 'Acrobacia' } })
      expect(err).to be_nil
      expect(next_ai['phase']).to eq('hit_determined')
      expect(next_ai['contest']['defender_roll']).to include('total' => 14, 'skill' => 'Acrobacia')
      expect(next_ai['contest']['outcome']).to eq('source_wins')
      expect(next_ai['pending_responders'].first['responded']).to be true
    end

    it 'empate → defensor vence' do
      next_ai, err = described_class.apply_response(current, { character_id: 'def-1', defender_roll: { total: 18, skill: 'Atletismo' } })
      expect(err).to be_nil
      expect(next_ai['contest']['outcome']).to eq('target_wins')
    end

    it 'não muta o hash original (deep dup)' do
      described_class.apply_response(current, { character_id: 'def-1', defender_roll: { total: 5 } })
      expect(current['phase']).to eq('roll')
      expect(current['contest']['defender_roll']).to be_nil
    end

    it 'erro :not_found para interação vazia' do
      _, err = described_class.apply_response(nil, { character_id: 'def-1', defender_roll: { total: 5 } })
      expect(err).to eq(:not_found)
    end

    it 'erro :not_pending para responder fora da lista' do
      _, err = described_class.apply_response(current, { character_id: 'other', defender_roll: { total: 5 } })
      expect(err).to eq(:not_pending)
    end

    it 'erro :invalid_roll sem total' do
      _, err = described_class.apply_response(current, { character_id: 'def-1', defender_roll: { skill: 'Acrobacia' } })
      expect(err).to eq(:invalid_roll)
    end

    it 'erro :invalid_skill para perícia fora das opções' do
      _, err = described_class.apply_response(current, { character_id: 'def-1', defender_roll: { total: 10, skill: 'Furtividade' } })
      expect(err).to eq(:invalid_skill)
    end

    it 'permite o atacante preencher attacker_roll no respond se ausente no upsert' do
      late = described_class.build_contest(kind: 'contest', source_id: 'atk-1', target_ids: ['def-1'])
      expect(late['contest']['attacker_roll']).to be_nil
      next_ai, err = described_class.apply_response(late, {
        character_id: 'def-1',
        attacker_roll: { total: 20 },
        defender_roll: { total: 10, skill: 'Atletismo' },
      })
      expect(err).to be_nil
      expect(next_ai['contest']['attacker_roll']).to include('total' => 20)
      expect(next_ai['contest']['outcome']).to eq('source_wins')
    end
  end

  describe '.build_opportunity_attack' do
    let(:oa_params) do
      {
        kind: 'opportunity_attack',
        source_id: 'reactor-1',
        target_ids: ['mover-1'],
        pending_responders: [{ character_id: 'reactor-1', need: 'offer_reaction', owned_by_dm: false, responded: false }],
        opportunity_attack: {
          mover_token_id: 'tok-mover',
          mover_name: 'Goblin',
          mover_combatant_id: 99,
          reactor_token_id: 'tok-reactor',
          reactor_name: 'Aragorn',
          attacks: [{ name: 'Espada Longa', damage_type: 'cortante' }],
          npc_attacks: [],
          ignores_disengage: false,
          oa_at_disadvantage: false,
        },
      }
    end

    it 'monta o OA na fase roll com o reator como pending responder' do
      ai = described_class.build_opportunity_attack(oa_params)
      expect(ai['kind']).to eq('opportunity_attack')
      expect(ai['phase']).to eq('roll')
      expect(ai['source_id']).to eq('reactor-1')
      expect(ai['target_ids']).to eq(['mover-1'])
      expect(ai['id']).to be_present
      expect(ai['pending_responders']).to eq([
        { 'character_id' => 'reactor-1', 'need' => 'offer_reaction', 'owned_by_dm' => false, 'responded' => false },
      ])
      expect(ai['label']).to eq('Ataque de Oportunidade')
    end

    it 'preserva o bloco opportunity_attack (tokens/nomes/ataques)' do
      ai = described_class.build_opportunity_attack(oa_params)
      oa = ai['opportunity_attack']
      expect(oa['mover_token_id']).to eq('tok-mover')
      expect(oa['mover_name']).to eq('Goblin')
      expect(oa['mover_combatant_id']).to eq(99)
      expect(oa['reactor_token_id']).to eq('tok-reactor')
      expect(oa['attacks']).to eq([{ 'name' => 'Espada Longa', 'damage_type' => 'cortante' }])
      expect(oa['npc_attacks']).to eq([])
      expect(oa['ignores_disengage']).to be false
      expect(oa['oa_at_disadvantage']).to be false
    end

    it 'marca owned_by_dm quando o reator é NPC do DM' do
      params = oa_params.deep_dup
      params[:pending_responders].first[:owned_by_dm] = true
      ai = described_class.build_opportunity_attack(params)
      expect(ai['pending_responders'].first['owned_by_dm']).to be true
    end

    it 'retorna nil sem source_id (reator)' do
      expect(described_class.build_opportunity_attack(oa_params.merge(source_id: ''))).to be_nil
    end

    it 'retorna nil sem target_ids (mover)' do
      expect(described_class.build_opportunity_attack(oa_params.merge(target_ids: []))).to be_nil
    end

    it 'retorna nil sem bloco opportunity_attack' do
      expect(described_class.build_opportunity_attack(oa_params.merge(opportunity_attack: nil))).to be_nil
    end

    it 'retorna nil para kind diferente' do
      expect(described_class.build_opportunity_attack(oa_params.merge(kind: 'contest'))).to be_nil
    end
  end

  describe '.apply_response (opportunity_attack)' do
    let(:current) do
      described_class.build_opportunity_attack(
        kind: 'opportunity_attack',
        source_id: 'reactor-1',
        target_ids: ['mover-1'],
        opportunity_attack: { mover_combatant_id: 99, reactor_name: 'R', mover_name: 'M' },
      )
    end

    it 'grava roll/damage, marca responded e avança para resolved' do
      next_ai, err = described_class.apply_response(current, {
        character_id: 'reactor-1',
        opportunity_attack: { roll: { total: 17 }, damage: 6 },
      })
      expect(err).to be_nil
      expect(next_ai['phase']).to eq('resolved')
      expect(next_ai['opportunity_attack']['roll']).to include('total' => 17)
      expect(next_ai['opportunity_attack']['damage']).to eq(6)
      expect(next_ai['pending_responders'].first['responded']).to be true
    end

    it 'não muta o hash original (deep dup)' do
      described_class.apply_response(current, { character_id: 'reactor-1', opportunity_attack: { roll: { total: 17 }, damage: 6 } })
      expect(current['phase']).to eq('roll')
      expect(current['opportunity_attack']['roll']).to be_nil
    end

    it 'erro :invalid_roll sem total' do
      _, err = described_class.apply_response(current, { character_id: 'reactor-1', opportunity_attack: { damage: 6 } })
      expect(err).to eq(:invalid_roll)
    end

    it 'erro :not_pending para responder fora da lista' do
      _, err = described_class.apply_response(current, { character_id: 'outro', opportunity_attack: { roll: { total: 17 }, damage: 6 } })
      expect(err).to eq(:not_pending)
    end
  end
end
