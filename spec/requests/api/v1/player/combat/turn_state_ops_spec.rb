# frozen_string_literal: true

require 'rails_helper'

# Ops granulares e versionadas do `turn_state`.
#
# A regressao que estas specs guardam: com o REPLACE integral antigo, duas
# escritas concorrentes se desfaziam — a segunda, montada sobre uma leitura
# anterior, RESSUSCITAVA a chave que a primeira apagou (foi assim que um TR
# imposto ficou preso quando o alvo gastou a Inspiracao Bardica).
RSpec.describe 'Api::V1::Player::Combat turn_state ops', type: :request do
  let(:dm_role)     { Role.find_or_create_by!(name: 'DM') }
  let(:player_role) { Role.find_or_create_by!(name: 'Player') }

  let(:dm)       { create(:user, role: dm_role) }
  let(:player)   { create(:user, role: player_role) }
  let(:outsider) { create(:user, role: player_role) }

  let(:schedule) { create(:schedule) }
  let!(:player_character) { create(:character, user: player, group: schedule.group) }

  let(:dm_headers)       { bearer_headers_for(dm) }
  let(:player_headers)   { bearer_headers_for(player) }
  let(:outsider_headers) { bearer_headers_for(outsider) }

  let!(:cs) { create(:combat_state, schedule: schedule, active: true, round: 1) }
  let!(:combatant) do
    create(:combat_combatant, combat_state: cs, combatable: player_character, position: 0,
                              turn_state: { 'pendingTargetSave' => { 'dc' => 15 }, 'bardicInspiration' => { 'die' => 'd6' } })
  end

  def path(id = combatant.id)
    "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{id}/turn_state"
  end

  describe 'aplicacao das ops' do
    it 'delete remove SO a chave pedida' do
      patch path, params: { ops: [{ op: 'delete', key: 'pendingTargetSave' }] },
                  headers: dm_headers, as: :json

      expect(response).to have_http_status(:ok)
      ts = combatant.reload.turn_state
      expect(ts).not_to have_key('pendingTargetSave')
      expect(ts['bardicInspiration']).to eq('die' => 'd6')
    end

    it 'set grava a chave sem tocar nas demais' do
      patch path, params: { ops: [{ op: 'set', key: 'countercharm', value: { 'activatedRound' => 2 } }] },
                  headers: dm_headers, as: :json

      expect(response).to have_http_status(:ok)
      ts = combatant.reload.turn_state
      expect(ts['countercharm']).to eq('activatedRound' => 2)
      expect(ts['pendingTargetSave']).to eq('dc' => 15)
    end

    it 'merge funde raso no objeto existente' do
      patch path, params: { ops: [{ op: 'merge', key: 'pendingTargetSave', value: { 'saveBonus' => 3 } }] },
                  headers: dm_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(combatant.reload.turn_state['pendingTargetSave']).to eq('dc' => 15, 'saveBonus' => 3)
    end

    it 'aplica varias ops na ordem, atomicamente' do
      patch path, params: { ops: [
        { op: 'delete', key: 'bardicInspiration' },
        { op: 'delete', key: 'pendingTargetSave' },
        { op: 'set', key: 'lastSaveResult', value: 'success' },
      ] }, headers: dm_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(combatant.reload.turn_state).to eq('lastSaveResult' => 'success')
    end

    it 'rejeita op desconhecida sem gravar nada' do
      patch path, params: { ops: [{ op: 'increment', key: 'x' }] }, headers: dm_headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(combatant.reload.turn_state).to have_key('pendingTargetSave')
    end

    it 'rejeita corpo sem array de ops' do
      patch path, params: { ops: 'delete tudo' }, headers: dm_headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'versionamento' do
    it 'incrementa turn_state_rev e devolve no corpo' do
      before_rev = combatant.turn_state_rev

      patch path, params: { ops: [{ op: 'delete', key: 'bardicInspiration' }] },
                  headers: dm_headers, as: :json

      expect(response.parsed_body['combatant']['turn_state_rev']).to eq(before_rev + 1)
    end

    it 'base_rev correta grava' do
      patch path, params: { ops: [{ op: 'delete', key: 'bardicInspiration' }], base_rev: combatant.turn_state_rev },
                  headers: dm_headers, as: :json

      expect(response).to have_http_status(:ok)
    end

    it 'base_rev velha da 409 e NAO grava' do
      stale = combatant.turn_state_rev
      combatant.update!(turn_state: combatant.turn_state.merge('outra' => 1)) # alguem escreveu no meio

      patch path, params: { ops: [{ op: 'delete', key: 'pendingTargetSave' }], base_rev: stale },
                  headers: dm_headers, as: :json

      expect(response).to have_http_status(:conflict)
      expect(combatant.reload.turn_state).to have_key('pendingTargetSave')
      # devolve o estado atual para o cliente reconciliar sem GET extra
      expect(response.parsed_body.dig('combatant', 'turn_state')).to have_key('outra')
    end

    it 'a valvula REPLACE antiga tambem versiona (senao o eco pareceria stale)' do
      expect { combatant.update!(turn_state: { 'x' => 1 }) }
        .to change { combatant.reload.turn_state_rev }.by(1)
    end

    it 'escrita que nao toca turn_state nao versiona' do
      expect { combatant.update!(hp_current: 5) }
        .not_to change { combatant.reload.turn_state_rev }
    end
  end

  describe 'a regressao que motivou o endpoint' do
    it 'duas intencoes DISJUNTAS nao se desfazem (a 2a nao ressuscita a chave da 1a)' do
      # Cenario Aberama: um comando gasta o dado; outro resolve o TR. No REPLACE
      # integral, o 2o (montado sobre leitura anterior) repunha o pendingTargetSave.
      patch path, params: { ops: [{ op: 'delete', key: 'bardicInspiration' }] },
                  headers: dm_headers, as: :json
      patch path, params: { ops: [{ op: 'delete', key: 'pendingTargetSave' }] },
                  headers: dm_headers, as: :json

      ts = combatant.reload.turn_state
      expect(ts).not_to have_key('bardicInspiration')
      expect(ts).not_to have_key('pendingTargetSave')
    end
  end

  describe 'autorizacao' do
    it 'o DM da mesa pode' do
      patch path, params: { ops: [{ op: 'delete', key: 'bardicInspiration' }] }, headers: dm_headers, as: :json
      expect(response).to have_http_status(:ok)
    end

    it 'o dono do combatente pode (resolver o proprio TR fora do turno dele)' do
      patch path, params: { ops: [{ op: 'delete', key: 'pendingTargetSave' }] },
                  headers: player_headers, as: :json
      expect(response).to have_http_status(:ok)
    end

    it 'quem nao e da mesa NAO pode' do
      patch path, params: { ops: [{ op: 'delete', key: 'pendingTargetSave' }] },
                  headers: outsider_headers, as: :json
      expect(response.status).to be_in([403, 404])
      expect(combatant.reload.turn_state).to have_key('pendingTargetSave')
    end

    it 'jogador NAO mexe no turn_state de outro combatente fora do seu turno' do
      npc = create(:combat_npc, schedule: schedule)
      other = create(:combat_combatant, :npc, combat_state: cs, combatable: npc, position: 1,
                                              turn_state: { 'pendingTargetSave' => { 'dc' => 10 } })
      cs.update!(current_turn_index: 1) if cs.respond_to?(:current_turn_index)

      patch path(other.id), params: { ops: [{ op: 'delete', key: 'pendingTargetSave' }] },
                            headers: player_headers, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(other.reload.turn_state).to have_key('pendingTargetSave')
    end
  end
end
