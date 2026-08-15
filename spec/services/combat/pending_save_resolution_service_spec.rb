# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Combat::PendingSaveResolutionService, type: :service do
  let(:player_role) { Role.find_or_create_by!(name: 'Player') }
  let(:owner) { create(:user, role: player_role) }
  let(:outsider) { create(:user, role: player_role) }
  let(:schedule) { create(:schedule) }
  let(:character) { create(:character, user: owner, group: schedule.group) }
  let(:combat_state) { create(:combat_state, schedule: schedule, active: true, round: 3) }
  let(:roll_group_id) { 'rg-shatter-lira' }
  let(:pending) do
    {
      'saveId' => 'aoe-save',
      'ability' => 'con',
      'dc' => 15,
      'saveBonus' => 2,
      'sourceActorKey' => '',
      'sourceActorName' => 'Darkmenos',
      'sourceLabel' => 'Despedaçar',
      'emoji' => '💥',
      'onFailCondition' => '',
      'effectLabel' => '',
      'appliedRound' => 3,
      'aoeDamage' => 15,
      'aoeDamageType' => 'trovao',
      'aoeHalfOnSave' => true,
      'cardRollGroupId' => roll_group_id,
    }
  end
  let(:combatant) do
    create(
      :combat_combatant,
      combat_state: combat_state,
      combatable: character,
      position: 0,
      hp_current: 30,
      hp_max: 30,
      turn_state: { 'pendingTargetSave' => pending, 'rageRoundsRemaining' => 8 },
    )
  end

  def resolve(d20:, user: owner, bardic_bonus: nil, d20_alt: nil, advantage: nil)
    described_class.call(
      combatant: combatant,
      current_user: user,
      d20: d20,
      save_id: 'aoe-save',
      card_roll_group_id: roll_group_id,
      bardic_bonus: bardic_bonus,
      d20_alt: d20_alt,
      advantage: advantage,
    )
  end

  before do
    SessionFeed::Persist.call(
      schedule_id: schedule.id,
      normalized: {
        'kind' => 'roll', 'id' => 'roll-save-1', 'timestamp' => 1_700_000_000_000,
        'sessionId' => schedule.id.to_s, 'rollGroupId' => roll_group_id,
        'playerName' => 'DM', 'characterName' => 'Darkmenos', 'type' => 'save',
        'label' => 'TR CON', 'total' => 0, 'breakdown' => '',
        'savePrompt' => { 'dc' => 15, 'ability' => 'con', 'targetName' => 'Lira' },
      },
    )
  end

  it 'aplica dano, limpa o pending, marca dano de furia e grava o log na mesma resolucao' do
    result = resolve(d20: 5)

    expect(result).to be_success
    expect(result.result[:save]).to include(success: false, total: 7)
    expect(result.result[:damage_applied]).to eq(15)
    expect(combatant.reload.hp_current).to eq(15)
    expect(combatant.turn_state).not_to have_key('pendingTargetSave')
    expect(combatant.turn_state['rageTookDamageSinceLastTurn']).to be(true)
    expect(result.result[:log].message).to include('sofre 15 de dano')
    expect(SessionFeedItem.find_by(roll_group_id: roll_group_id).payload.dig('savePrompt', 'resolved')).to be(true)
  end

  it 'aplica metade no sucesso e nenhum dano no Nat 20' do
    success = resolve(d20: 15)
    expect(success.result[:damage_applied]).to eq(7)
    expect(combatant.reload.hp_current).to eq(23)

    combatant.update!(hp_current: 30, turn_state: { 'pendingTargetSave' => pending })
    critical = resolve(d20: 20)
    expect(critical.result[:save]).to include(success: true, critical_success: true)
    expect(critical.result[:damage_applied]).to eq(0)
    expect(combatant.reload.hp_current).to eq(30)
  end

  it 'dobra no Nat 1' do
    result = resolve(d20: 1)
    expect(result.result[:save]).to include(success: false, critical_failure: true)
    expect(result.result[:damage_applied]).to eq(30)
    expect(combatant.reload.hp_current).to eq(0)
  end

  it 'first-write-wins: uma segunda aba nao reaplica o mesmo pending' do
    first = resolve(d20: 5)
    second = resolve(d20: 5)

    expect(first).to be_success
    expect(second).not_to be_success
    expect(second.errors[:conflict]).to be_present
    expect(combatant.reload.hp_current).to eq(15)
    expect(schedule.session_logs.where("message LIKE '%sofre 15 de dano%'").count).to eq(1)
  end

  it 'recusa usuario que nao controla alvo, fonte ou mesa' do
    result = resolve(d20: 5, user: outsider)

    expect(result).not_to be_success
    expect(result.errors[:authorization]).to be_present
    expect(combatant.reload.hp_current).to eq(30)
    expect(combatant.turn_state).to have_key('pendingTargetSave')
  end

  it 'deriva falha automatica de condicao persistida, ignorando o d20' do
    pending['ability'] = 'dex'
    combatant.update!(conditions: [{ 'id' => 'atordoado', 'turns_left' => 0 }])
    result = resolve(d20: 20)

    expect(result.result[:save]).to include(auto_fail: true, d20: 0, success: false)
    expect(result.result[:damage_applied]).to eq(15)
  end

  describe 'Inspiração Bárdica somada ao TR (server-authoritative)' do
    let(:inspired_turn_state) do
      {
        'pendingTargetSave' => pending,
        'bardicInspiration' => { 'die' => 'd8', 'grantedBy' => 'cb-bardo', 'expiresAtRound' => 103 },
      }
    end

    it 'soma o dado ao total e CONSOME a inspiração na mesma transação' do
      combatant.update!(turn_state: inspired_turn_state)
      # d20 12 + saveBonus 2 = 14 (falha vs CD 15); com +5 do dado = 19 → sucesso.
      result = resolve(d20: 12, bardic_bonus: 5)

      expect(result).to be_success
      expect(result.result[:save][:total]).to eq(19)
      expect(result.result[:save][:success]).to be(true)
      expect(combatant.reload.turn_state).not_to have_key('bardicInspiration')
      expect(combatant.turn_state).not_to have_key('pendingTargetSave')
    end

    it 'limita o bônus às faces do dado concedido (cliente não inventa)' do
      combatant.update!(turn_state: inspired_turn_state)
      result = resolve(d20: 12, bardic_bonus: 99)

      expect(result).to be_success
      # d8 → no máximo 8: 12 + 2 + 8 = 22
      expect(result.result[:save][:total]).to eq(22)
    end

    it 'recusa o bônus quando o alvo não carrega dado nenhum' do
      result = resolve(d20: 12, bardic_bonus: 5)

      expect(result).not_to be_success
      expect(result.errors).to have_key(:bardic_bonus)
      # nada foi aplicado: o pending continua para ser resolvido de novo
      expect(combatant.reload.turn_state).to have_key('pendingTargetSave')
    end

    it 'sem bônus, o dado do alvo continua intacto' do
      combatant.update!(turn_state: inspired_turn_state)
      resolve(d20: 18)

      expect(combatant.reload.turn_state['bardicInspiration']).to include('die' => 'd8')
    end
  end

  # Fase 0 da Cancao de Protecao (Bardo L6): o TR imposto passa a aceitar duas
  # faces. QUEM ESCOLHE e o servidor — o cliente so rola e diz o modo.
  describe 'vantagem/desvantagem no TR' do
    it 'vantagem usa a MAIOR face e registra a descartada' do
      # d20 4 + bonus 2 = 6 (falha vs CD 15); com a face 17 vira 19 -> sucesso
      result = resolve(d20: 4, d20_alt: 17, advantage: 'advantage')

      expect(result).to be_success
      save = result.result[:save]
      expect(save[:d20]).to eq(17)
      expect(save[:d20_alt]).to eq(4)
      expect(save[:advantage]).to eq('advantage')
      expect(save[:total]).to eq(19)
      expect(save[:success]).to be(true)
      expect(save[:breakdown]).to include('descartado 4')
    end

    it 'desvantagem usa a MENOR face' do
      result = resolve(d20: 19, d20_alt: 3, advantage: 'disadvantage')

      save = result.result[:save]
      expect(save[:d20]).to eq(3)
      expect(save[:success]).to be(false)
    end

    it 'o cliente NAO escolhe: mandar so a face boa sem a 2a nao vira vantagem' do
      result = resolve(d20: 17, advantage: 'advantage')

      save = result.result[:save]
      expect(save[:advantage]).to eq('normal')
      expect(save[:d20]).to eq(17)
      expect(save[:d20_alt]).to be_nil
    end

    it 'face alternativa fora de 1..20 e recusada' do
      result = resolve(d20: 10, d20_alt: 44, advantage: 'advantage')

      expect(result).not_to be_success
      expect(result.errors).to have_key(:d20_alt)
      expect(combatant.reload.turn_state).to have_key('pendingTargetSave')
    end

    it 'Nat 20 vale pela face ESCOLHIDA (vantagem transforma o TR em critico)' do
      result = resolve(d20: 2, d20_alt: 20, advantage: 'advantage')

      save = result.result[:save]
      expect(save[:critical_success]).to be(true)
      expect(result.result[:damage_applied]).to eq(0)
    end
  end
end
