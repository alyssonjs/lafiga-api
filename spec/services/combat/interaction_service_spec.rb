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

  describe '.build_hostile_casting (Frustrar Conjuração)' do
    let(:hc_params) do
      {
        kind: 'hostile_casting',
        source_id: 'caster-npc-1',
        target_ids: ['desistente-1'],
        pending_responders: [{ character_id: 'desistente-1', need: 'offer_reaction', owned_by_dm: false, responded: false }],
        hostile_casting: { caster_id: 'caster-npc-1', caster_name: 'Cultista', spell_name: 'Enfeitiçar Pessoa', spell_level: 1, dc: 14 },
      }
    end

    it 'monta na fase declared com os reatores como pending offer_reaction' do
      ai = described_class.build_hostile_casting(hc_params)
      expect(ai['kind']).to eq('hostile_casting')
      expect(ai['phase']).to eq('declared')
      expect(ai['source_id']).to eq('caster-npc-1')
      expect(ai['target_ids']).to eq(['desistente-1'])
      expect(ai['id']).to be_present
      expect(ai['pending_responders']).to eq([
        { 'character_id' => 'desistente-1', 'need' => 'offer_reaction', 'owned_by_dm' => false, 'responded' => false },
      ])
      expect(ai['label']).to eq('Conjuração hostil')
    end

    it 'preserva o bloco hostile_casting (nome/nível/CD) + hostile true e outcome nil' do
      hc = described_class.build_hostile_casting(hc_params)['hostile_casting']
      expect(hc['caster_id']).to eq('caster-npc-1')
      expect(hc['caster_name']).to eq('Cultista')
      expect(hc['spell_name']).to eq('Enfeitiçar Pessoa')
      expect(hc['spell_level']).to eq(1)
      expect(hc['dc']).to eq(14)
      expect(hc['hostile']).to be true
      expect(hc).to have_key('outcome')
      expect(hc['outcome']).to be_nil
    end

    it 'suporta múltiplos reatores (todos viram offer_reaction)' do
      params = hc_params.merge(target_ids: %w[d-1 d-2])
      ai = described_class.build_hostile_casting(params)
      expect(ai['pending_responders'].map { |r| r['character_id'] }).to eq(%w[d-1 d-2])
      expect(ai['pending_responders'].map { |r| r['need'] }.uniq).to eq(['offer_reaction'])
    end

    it 'retorna nil sem source_id (conjurador)' do
      expect(described_class.build_hostile_casting(hc_params.merge(source_id: ''))).to be_nil
    end

    it 'retorna nil sem target_ids (reatores)' do
      expect(described_class.build_hostile_casting(hc_params.merge(target_ids: []))).to be_nil
    end

    it 'retorna nil sem o bloco hostile_casting' do
      expect(described_class.build_hostile_casting(hc_params.merge(hostile_casting: nil))).to be_nil
    end

    it 'retorna nil para kind diferente' do
      expect(described_class.build_hostile_casting(hc_params.merge(kind: 'contest'))).to be_nil
    end
  end

  describe '.build_target_consent (Consentimento de Alvo)' do
    let(:tc_params) do
      {
        kind: 'target_consent',
        source_id: 'caster-1',
        target_ids: ['pc-alvo-1'],
        pending_responders: [{ character_id: 'pc-alvo-1', need: 'consent', owned_by_dm: false, responded: false }],
        target_consent: { caster_id: 'caster-1', caster_name: 'Clériga', spell_name: 'Palavra Curativa', beneficial: true, auto_refuse: true },
      }
    end

    it 'monta na fase declared com o alvo pendente need consent' do
      ai = described_class.build_target_consent(tc_params)
      expect(ai['kind']).to eq('target_consent')
      expect(ai['phase']).to eq('declared')
      expect(ai['source_id']).to eq('caster-1')
      expect(ai['target_ids']).to eq(['pc-alvo-1'])
      expect(ai['pending_responders']).to eq([
        { 'character_id' => 'pc-alvo-1', 'need' => 'consent', 'owned_by_dm' => false, 'responded' => false },
      ])
      expect(ai['label']).to eq('Consentimento de alvo')
    end

    it 'preserva o bloco target_consent (conjurador/magia/benéfico/auto-recusa)' do
      tc = described_class.build_target_consent(tc_params)['target_consent']
      expect(tc['caster_name']).to eq('Clériga')
      expect(tc['spell_name']).to eq('Palavra Curativa')
      expect(tc['beneficial']).to be true
      expect(tc['auto_refuse']).to be true
      expect(tc).to have_key('outcome')
    end

    it 'marca owned_by_dm quando o alvo é NPC do DM' do
      params = tc_params.deep_dup
      params[:pending_responders].first[:owned_by_dm] = true
      ai = described_class.build_target_consent(params)
      expect(ai['pending_responders'].first['owned_by_dm']).to be true
    end

    it 'retorna nil sem source_id / sem target_ids / sem bloco / kind diferente' do
      expect(described_class.build_target_consent(tc_params.merge(source_id: ''))).to be_nil
      expect(described_class.build_target_consent(tc_params.merge(target_ids: []))).to be_nil
      expect(described_class.build_target_consent(tc_params.merge(target_consent: nil))).to be_nil
      expect(described_class.build_target_consent(tc_params.merge(kind: 'contest'))).to be_nil
    end
  end

  describe '.build_protective_swap (Fúria Protetora: Trocar de Lugar)' do
    let(:ps_params) do
      {
        kind: 'protective_swap',
        source_id: 'prot-1',
        pending_responders: [{ character_id: 'prot-1', need: 'offer_reaction', owned_by_dm: false, responded: false }],
        protective_swap: {
          reactor_char_id: 'prot-1',
          ally_char_id: 'ally-1',
          ally_owned_by_dm: false,
          attacker_token_id: 'tk-foe',
          ally_token_id: 'tk-ally',
          reactor_token_id: 'tk-prot',
          attack_meta: { name: 'Espada Longa', caster_name: 'Ogro', bonus: '+5', damage: '1d8+3', damage_type: 'cortante' },
        },
      }
    end

    it 'monta na fase awaiting_protector com o Protetor pendente (need offer_reaction)' do
      ai = described_class.build_protective_swap(ps_params)
      expect(ai['kind']).to eq('protective_swap')
      expect(ai['phase']).to eq('awaiting_protector')
      expect(ai['source_id']).to eq('prot-1')
      expect(ai['target_ids']).to eq(['prot-1'])
      expect(ai['id']).to be_present
      expect(ai['pending_responders']).to eq([
        { 'character_id' => 'prot-1', 'need' => 'offer_reaction', 'owned_by_dm' => false, 'responded' => false },
      ])
      expect(ai['label']).to eq('Fúria Protetora: Trocar de Lugar')
    end

    it 'preserva o bloco protective_swap (chars/tokens/attack_meta) + outcome nil' do
      ps = described_class.build_protective_swap(ps_params)['protective_swap']
      expect(ps['reactor_char_id']).to eq('prot-1')
      expect(ps['ally_char_id']).to eq('ally-1')
      expect(ps['ally_owned_by_dm']).to be false
      expect(ps['attacker_token_id']).to eq('tk-foe')
      expect(ps['ally_token_id']).to eq('tk-ally')
      expect(ps['reactor_token_id']).to eq('tk-prot')
      expect(ps['attack_meta']).to eq(
        'name' => 'Espada Longa', 'caster_name' => 'Ogro', 'bonus' => '+5',
        'damage' => '1d8+3', 'damage_type' => 'cortante',
      )
      expect(ps).to have_key('outcome')
      expect(ps['outcome']).to be_nil
    end

    it 'marca ally_owned_by_dm quando o aliado é NPC do DM' do
      params = ps_params.deep_dup
      params[:protective_swap][:ally_owned_by_dm] = true
      ps = described_class.build_protective_swap(params)['protective_swap']
      expect(ps['ally_owned_by_dm']).to be true
    end

    it 'retorna nil sem reactor_char_id / sem ally_char_id / sem bloco / kind diferente' do
      no_reactor = ps_params.deep_dup.tap { |h| h[:protective_swap].delete(:reactor_char_id); h.delete(:source_id) }
      no_ally    = ps_params.deep_dup.tap { |h| h[:protective_swap].delete(:ally_char_id) }
      expect(described_class.build_protective_swap(no_reactor)).to be_nil
      expect(described_class.build_protective_swap(no_ally)).to be_nil
      expect(described_class.build_protective_swap(ps_params.merge(protective_swap: nil))).to be_nil
      expect(described_class.build_protective_swap(ps_params.merge(kind: 'contest'))).to be_nil
    end
  end

  describe '.build_tribe_defender (Defensor da Tribo)' do
    let(:td_params) do
      {
        kind: 'tribe_defender',
        source_id: 'def-1',
        pending_responders: [{ character_id: 'def-1', need: 'offer_reaction', owned_by_dm: false, responded: false }],
        tribe_defender: {
          defender_char_id: 'def-1',
          ally_char_id: 'ally-1',
          ally_owned_by_dm: false,
          defender_token_id: 'tk-def',
          ally_token_id: 'tk-ally',
          downed_name: 'Aliado Caído',
        },
      }
    end

    it 'monta na fase declared com o Defensor pendente (need offer_reaction)' do
      ai = described_class.build_tribe_defender(td_params)
      expect(ai['kind']).to eq('tribe_defender')
      expect(ai['phase']).to eq('declared')
      expect(ai['source_id']).to eq('def-1')
      expect(ai['target_ids']).to eq(['def-1'])
      expect(ai['id']).to be_present
      expect(ai['pending_responders']).to eq([
        { 'character_id' => 'def-1', 'need' => 'offer_reaction', 'owned_by_dm' => false, 'responded' => false },
      ])
      expect(ai['label']).to eq('Defensor da Tribo')
    end

    it 'preserva o bloco tribe_defender (chars/tokens/nome) + outcome nil' do
      td = described_class.build_tribe_defender(td_params)['tribe_defender']
      expect(td['defender_char_id']).to eq('def-1')
      expect(td['ally_char_id']).to eq('ally-1')
      expect(td['ally_owned_by_dm']).to be false
      expect(td['defender_token_id']).to eq('tk-def')
      expect(td['ally_token_id']).to eq('tk-ally')
      expect(td['downed_name']).to eq('Aliado Caído')
      expect(td).to have_key('outcome')
      expect(td['outcome']).to be_nil
    end

    it 'retorna nil sem defender_char_id / sem ally_char_id / sem bloco / kind diferente' do
      no_def = td_params.deep_dup.tap { |h| h[:tribe_defender].delete(:defender_char_id); h.delete(:source_id) }
      no_ally = td_params.deep_dup.tap { |h| h[:tribe_defender].delete(:ally_char_id) }
      expect(described_class.build_tribe_defender(no_def)).to be_nil
      expect(described_class.build_tribe_defender(no_ally)).to be_nil
      expect(described_class.build_tribe_defender(td_params.merge(tribe_defender: nil))).to be_nil
      expect(described_class.build_tribe_defender(td_params.merge(kind: 'contest'))).to be_nil
    end
  end
end
