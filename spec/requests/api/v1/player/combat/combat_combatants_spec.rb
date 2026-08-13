# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Player::Combat::CombatCombatantsController', type: :request do
  let(:dm_role)     { Role.find_or_create_by!(name: 'DM') }
  let(:player_role) { Role.find_or_create_by!(name: 'Player') }

  let(:dm)        { create(:user, role: dm_role) }
  let(:player)    { create(:user, role: player_role) }
  let(:outsider)  { create(:user, role: player_role) }

  let(:schedule)  { create(:schedule) }
  let!(:player_character) { create(:character, user: player, group: schedule.group) }

  let(:dm_headers)        { bearer_headers_for(dm) }
  let(:player_headers)    { bearer_headers_for(player) }
  let(:outsider_headers)  { bearer_headers_for(outsider) }

  let!(:cs) { create(:combat_state, schedule: schedule, active: true, round: 1) }

  describe 'GET index' do
    it 'lists combatants in position order for a member' do
      npc = create(:combat_npc, schedule: schedule)
      a = create(:combat_combatant, combat_state: cs, combatable: player_character, position: 1)
      b = create(:combat_combatant, :npc, combat_state: cs, combatable: npc, position: 0)

      get "/api/v1/player/schedules/#{schedule.id}/combat_combatants", headers: player_headers
      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['combatants'].pluck('id')
      expect(ids).to eq([b.id, a.id])
    end

    it '200 for outsider (hub read)' do
      get "/api/v1/player/schedules/#{schedule.id}/combat_combatants", headers: outsider_headers
      expect(response).to have_http_status(:ok)
    end

    it 'returns empty list when there is no combat_state yet' do
      cs.destroy!
      get "/api/v1/player/schedules/#{schedule.id}/combat_combatants", headers: player_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['combatants']).to eq([])
    end
  end

  describe 'POST create' do
    it 'creates a PC combatant with HP defaults from the Sheet (DM)' do
      sheet = create(:sheet, character: player_character, hp_current: 18, hp_max: 25)

      payload = {
        combatant: {
          type: 'pc',
          combatable_id: player_character.id,
          initiative: 14,
          initiative_bonus: 2,
        }
      }

      post "/api/v1/player/schedules/#{schedule.id}/combat_combatants",
           params: payload, headers: dm_headers, as: :json

      expect(response).to have_http_status(:created)
      json = response.parsed_body['combatant']
      expect(json).to include('name' => player_character.name, 'hp_current' => 18, 'hp_max' => 25, 'initiative' => 14)
    end

    it 'creates an NPC combatant copying HP from the CombatNpc' do
      npc = create(:combat_npc, schedule: schedule, hp_current: 9, hp_max: 9, ac: 14)

      post "/api/v1/player/schedules/#{schedule.id}/combat_combatants",
           params: { combatant: { type: 'npc', combatable_id: npc.id, initiative: 12, initiative_bonus: 1 } },
           headers: dm_headers, as: :json

      expect(response).to have_http_status(:created)
      json = response.parsed_body['combatant']
      expect(json).to include('hp_current' => 9, 'hp_max' => 9, 'ac' => 14)
    end

    # A CA de um combatente PC é AUTORITATIVA do summary da ficha (Defesa sem
    # Armadura do Bárbaro, escudo, feats, itens mágicos). O front ECOA um `ac` no
    # create, mas ele pode chegar STALE (ex.: escudo equipado depois do último
    # snapshot) — o controller deve IGNORAR o `ac` ecoado e usar o do summary,
    # senão o combate congela um valor antigo (bug: ficha 18 × combate 12).
    it 'PC: a CA vem do summary (autoritativa), ignorando o `ac` ecoado pelo front' do
      create(:sheet, character: player_character, hp_current: 30, hp_max: 30)
      cmd = CharacterSheetSummaryService.call(sheet_id: player_character.sheet.id, sync: false)
      authoritative_ac = cmd.success? ? cmd.result.dig(:equipment, :ac, :ac).to_i : 10
      stale_front_ac = authoritative_ac + 7 # valor "velho" que o front mandaria

      post "/api/v1/player/schedules/#{schedule.id}/combat_combatants",
           params: { combatant: { type: 'pc', combatable_id: player_character.id, initiative: 10, ac: stale_front_ac } },
           headers: dm_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['combatant']['ac']).to eq(authoritative_ac)
      expect(response.parsed_body['combatant']['ac']).not_to eq(stale_front_ac)
    end

    it 'NPC: continua honrando o `ac` enviado no create (o Mestre pode customizar)' do
      npc = create(:combat_npc, schedule: schedule, hp_current: 9, hp_max: 9, ac: 14)

      post "/api/v1/player/schedules/#{schedule.id}/combat_combatants",
           params: { combatant: { type: 'npc', combatable_id: npc.id, initiative: 12, ac: 17 } },
           headers: dm_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['combatant']['ac']).to eq(17)
    end

    it '422 when adding a Character from another group' do
      other_group = create(:group)
      foreign_char = create(:character, group: other_group)

      post "/api/v1/player/schedules/#{schedule.id}/combat_combatants",
           params: { combatant: { type: 'pc', combatable_id: foreign_char.id, initiative: 10, initiative_bonus: 0 } },
           headers: dm_headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it '403 when called by Player' do
      post "/api/v1/player/schedules/#{schedule.id}/combat_combatants",
           params: { combatant: { type: 'pc', combatable_id: player_character.id, initiative: 10 } },
           headers: player_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it '422 when the combat has not been started' do
      cs.destroy!
      post "/api/v1/player/schedules/#{schedule.id}/combat_combatants",
           params: { combatant: { type: 'pc', combatable_id: player_character.id, initiative: 10 } },
           headers: dm_headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH update' do
    let!(:combatant) { create(:combat_combatant, combat_state: cs, combatable: player_character, position: 0, hp_current: 20, hp_max: 20) }

    it 'updates conditions and actions_used' do
      payload = {
        combatant: {
          conditions: [{ id: 'poisoned', turns_left: 3 }],
          actions_used: { action: true, bonus_action: false, movement: true, reaction: false },
        }
      }
      patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}",
            params: payload, headers: dm_headers, as: :json

      expect(response).to have_http_status(:ok)
      json = response.parsed_body['combatant']
      expect(json['conditions']).to eq([{ 'id' => 'poisoned', 'turns_left' => 3 }])
      expect(json['actions_used']).to include('action' => true, 'movement' => true)
    end

    # Houserule "1 reação por RODADA": `reactionUsedRound` é um marcador
    # SERVER-OWNED (o front nunca o envia) que trava a reação como GASTA até o
    # fim da rodada. Ao virar o turno o front faz um reset DEFENSIVO reescrevendo
    # actions_used/turn_state inteiros — sem esta trava, esse PATCH "recarregaria"
    # a reação no mesmo round. Ver `apply_reaction_round_lock!` no controller e
    # `reset_turn_actions!` (a mesma regra na virada server-side).
    context 'trava de reação por rodada (reactionUsedRound server-owned)' do
      let(:reset_patch) do
        { combatant: {
          actions_used: { action: false, bonus_action: false, movement: false, reaction: false },
          turn_state: { attacksMade: 0 },
        } }
      end

      it 'preserva o marcador e mantém reaction=true quando o front reseta na MESMA rodada' do
        combatant.update!(
          actions_used: { 'action' => false, 'bonus_action' => false, 'movement' => false, 'reaction' => true },
          turn_state: { 'reactionUsedRound' => cs.round, 'guardingAlly' => 'token-x' },
        )
        patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}",
              params: reset_patch, headers: dm_headers, as: :json

        expect(response).to have_http_status(:ok)
        json = response.parsed_body['combatant']
        expect(json['actions_used']).to include('reaction' => true)            # reação continua gasta
        expect(json['turn_state']).to include('reactionUsedRound' => cs.round) # marcador preservado
      end

      it 'NÃO interfere numa RODADA NOVA (round > reactionUsedRound): a reação recarrega' do
        combatant.update!(
          actions_used: { 'action' => false, 'bonus_action' => false, 'movement' => false, 'reaction' => true },
          turn_state: { 'reactionUsedRound' => cs.round },
        )
        cs.update!(round: cs.round + 1)
        patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}",
              params: reset_patch, headers: dm_headers, as: :json

        expect(response).to have_http_status(:ok)
        json = response.parsed_body['combatant']
        expect(json['actions_used']).to include('reaction' => false)     # recarregou
        expect(json['turn_state']).not_to have_key('reactionUsedRound')  # front pôde limpar
      end

      it 'não força reaction quando não há marcador (reação normal, sem houserule)' do
        combatant.update!(turn_state: {})
        patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}",
              params: { combatant: { actions_used: { action: false, bonus_action: false, movement: false, reaction: false } } },
              headers: dm_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['combatant']['actions_used']).to include('reaction' => false)
      end

      # STAMP (economia de reação unificada): qualquer #update que TRANSICIONE
      # actions_used.reaction false→true sem carimbo vivo NASCE round-locked —
      # o backend carimba reactionUsedRound (server-owned). Cobre AO manual do
      # Mestre, retaliação e o funil de ações do front (que só marcavam o flag,
      # antes sem lock → reação presa).
      it 'STAMP: PATCH marcando reaction=true carimba reactionUsedRound = rodada atual' do
        combatant.update!(turn_state: {}, actions_used: { 'action' => false, 'bonus_action' => false, 'movement' => false, 'reaction' => false })
        patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}",
              params: { combatant: { actions_used: { action: false, bonus_action: false, movement: false, reaction: true } } },
              headers: dm_headers, as: :json

        expect(response).to have_http_status(:ok)
        json = response.parsed_body['combatant']
        expect(json['actions_used']).to include('reaction' => true)
        expect(json['turn_state']).to include('reactionUsedRound' => cs.round) # nasceu round-locked
      end

      it 'STAMP: PATCH só de actions_used PRESERVA outras chaves do turn_state ao carimbar' do
        combatant.update!(turn_state: { 'guardingAlly' => 'tk-x' }, actions_used: { 'action' => false, 'bonus_action' => false, 'movement' => false, 'reaction' => false })
        patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}",
              params: { combatant: { actions_used: { action: false, bonus_action: false, movement: false, reaction: true } } },
              headers: dm_headers, as: :json

        expect(response).to have_http_status(:ok)
        json = response.parsed_body['combatant']
        expect(json['turn_state']).to include('guardingAlly' => 'tk-x', 'reactionUsedRound' => cs.round)
      end

      it 'STAMP: guard de transição — reaction JÁ true sem carimbo (legado) NÃO cria carimbo espúrio' do
        combatant.update!(turn_state: {}, actions_used: { 'action' => false, 'bonus_action' => false, 'movement' => false, 'reaction' => true })
        patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}",
              params: { combatant: { actions_used: { action: false, bonus_action: false, movement: false, reaction: true } } },
              headers: dm_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['combatant']['turn_state']).not_to have_key('reactionUsedRound')
      end
    end

    it 'allows the owning player to set initiative once while it is nil' do
      combatant.update_column(:initiative, nil)
      patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}",
            params: { combatant: { initiative: 18 } }, headers: player_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(combatant.reload.initiative).to eq(18)
    end

    it '403 for Player when initiative is already set' do
      expect(combatant.reload.initiative).not_to be_nil
      patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}",
            params: { combatant: { initiative: 99 } }, headers: player_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    # turn_state — válvula genérica OPACA de estado de turno. O contrato é
    # round-trip: o backend persiste e devolve QUALQUER JSON aninhado sem
    # conhecer as chaves (espelho do teste de contrato do front). Dono do PC
    # pode mutar o do PRÓPRIO combatente (PLAYER_TURN_STATE_FIELDS); o de
    # terceiros continua exclusivo do DM (turn_state ∉ COMBAT_EFFECT_FIELDS).
    context 'turn_state (válvula opaca) round-trip' do
      let(:opaque_turn_state) { { attacksMade: 2, minhaChaveFutura: { x: 1 } } }
      let(:expected_turn_state) { { 'attacksMade' => 2, 'minhaChaveFutura' => { 'x' => 1 } } }

      it 'dono do PC grava turn_state com chave arbitrária aninhada e o hash volta intacto' do
        patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}",
              params: { combatant: { turn_state: opaque_turn_state } }, headers: player_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['combatant']['turn_state']).to eq(expected_turn_state)
        expect(combatant.reload.turn_state).to eq(expected_turn_state)

        # GET devolve o mesmo hash (round-trip completo pela serialização)
        get "/api/v1/player/schedules/#{schedule.id}/combat_combatants", headers: player_headers
        expect(response).to have_http_status(:ok)
        row = response.parsed_body['combatants'].find { |c| c['id'] == combatant.id }
        expect(row['turn_state']).to eq(expected_turn_state)
      end

      # O conjurante do TURNO pode gravar turn_state (ex.: pendingTargetSave/TR de uma
      # magia de AREA) em combatente de OUTRO — inclusive NPC do Mestre. turn_state esta
      # em COMBAT_EFFECT_ON_TURN_FIELDS. Sem isso, o AoE do jogador nao registrava o TR.
      it 'permite o jogador do TURNO gravar turn_state (TR de área) em combatente de OUTRO (NPC)' do
        npc = create(:combat_npc, schedule: schedule)
        npc_combatant = create(:combat_combatant, :npc, combat_state: cs, combatable: npc, position: 1)
        cs.update_column(:current_turn_index, combatant.position) # turno do PC do player (conjurante)

        patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{npc_combatant.id}",
              params: { combatant: { turn_state: opaque_turn_state } }, headers: player_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(npc_combatant.reload.turn_state).to eq(expected_turn_state)
      end

      it '403 ao gravar turn_state em combatente de OUTRO quando NÃO é o turno do jogador' do
        npc = create(:combat_npc, schedule: schedule)
        npc_combatant = create(:combat_combatant, :npc, combat_state: cs, combatable: npc, position: 1)
        cs.update_column(:current_turn_index, npc_combatant.position) # NÃO é o turno do player

        patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{npc_combatant.id}",
              params: { combatant: { turn_state: opaque_turn_state } }, headers: player_headers, as: :json

        expect(response).to have_http_status(:forbidden)
        expect(npc_combatant.reload.turn_state).to eq({})
      end

      it 'DM grava turn_state de qualquer combatente' do
        patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}",
              params: { combatant: { turn_state: opaque_turn_state } }, headers: dm_headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(combatant.reload.turn_state).to eq(expected_turn_state)
      end
    end

    # Broadcast realtime — SERVER-SIDE dos "sync anchors" do front (que sao
    # server-authoritative): o PATCH que muta turn_state/condicoes dispara
    # `combatant_upserted` no SessionRealtimeChannel, com o estado atualizado no
    # payload. Cobre F3.11 (frenzyActive), F6.10 (condicoes/supressao),
    # F10.16 (pending/lockout no turn_state), F14.14 (pending), M4.
    context 'broadcast realtime no update (sync anchors)' do
      def stream
        SessionRealtimeChannel.stream_name_for(schedule.id)
      end

      it 'F3.11/F10.16/F14.14 — PATCH turn_state dispara combatant_upserted com o turn_state no payload' do
        expect {
          patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}",
                params: { combatant: { turn_state: { frenzyActive: true, frenzyActivatedRound: 2 } } },
                headers: player_headers, as: :json
        }.to have_broadcasted_to(stream).with { |data|
          expect(data['event']).to eq('combatant_upserted')
          expect(data['payload']['turn_state']).to eq({ 'frenzyActive' => true, 'frenzyActivatedRound' => 2 })
        }
      end

      it 'F6.10/M4 — PATCH conditions dispara combatant_upserted com as condicoes no payload' do
        expect {
          patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}",
                params: { combatant: { conditions: [{ id: 'frightened', turns_left: 1 }] } },
                headers: player_headers, as: :json
        }.to have_broadcasted_to(stream).with { |data|
          expect(data['event']).to eq('combatant_upserted')
          expect(data['payload']['conditions']).to eq([{ 'id' => 'frightened', 'turns_left' => 1 }])
        }
      end

      # Bárbaro base F1.20/M4: a ATIVAÇÃO/TÉRMINO da Fúria vive em turn_state
      # (rageRoundsRemaining) — server-authoritative. O PATCH que a muta dispara
      # combatant_upserted com o estado, então TODOS os players veem a Fúria em
      # tempo real (não só quem clicou).
      it 'F1.20/M4 — PATCH turn_state com rageRoundsRemaining (Fúria) dispara combatant_upserted com o estado' do
        expect {
          patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}",
                params: { combatant: { turn_state: { rageRoundsRemaining: 10 } } },
                headers: player_headers, as: :json
        }.to have_broadcasted_to(stream).with { |data|
          expect(data['event']).to eq('combatant_upserted')
          expect(data['payload']['turn_state']).to eq({ 'rageRoundsRemaining' => 10 })
        }
      end

      # Bárbaro base F2.7: o Ataque Descuidado foi MIGRADO de character.classData
      # (que não broadcastava — gap de multiplayer) para turn_state do combatente,
      # como a Fúria. Assim a declaração sincroniza em tempo real e os inimigos de
      # TODOS os clientes veem a vulnerabilidade (ataques contra o bárbaro têm
      # vantagem) — não só o cliente que declarou.
      it 'F2.7 — PATCH turn_state com recklessUntilNextTurnActive dispara combatant_upserted com o estado' do
        expect {
          patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}",
                params: { combatant: { turn_state: { recklessUntilNextTurnActive: true } } },
                headers: player_headers, as: :json
        }.to have_broadcasted_to(stream).with { |data|
          expect(data['event']).to eq('combatant_upserted')
          expect(data['payload']['turn_state']).to eq({ 'recklessUntilNextTurnActive' => true })
        }
      end

      # Desistente L10 F10.24/M4: a supressão de item mágico vive em
      # turn_state.suppressedItem (server-authoritative). O PATCH que a grava
      # dispara combatant_upserted → todos os clientes veem a supressão + expiração.
      it 'F10.24 — PATCH turn_state com suppressedItem (Suprimir Item) dispara combatant_upserted com o estado' do
        expect {
          patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}",
                params: { combatant: { turn_state: { suppressedItem: { targetId: 't1', targetName: 'Ogro', rounds: 2 } } } },
                headers: player_headers, as: :json
        }.to have_broadcasted_to(stream).with { |data|
          expect(data['event']).to eq('combatant_upserted')
          expect(data['payload']['turn_state']).to eq({
            'suppressedItem' => { 'targetId' => 't1', 'targetName' => 'Ogro', 'rounds' => 2 },
          })
        }
      end

      # Desistente L14 F14.9/M4: o bônus da Fúria Absorvente vive em
      # turn_state.rageAbsorbBonus/rageAbsorbRounds (server-authoritative). O PATCH
      # dispara combatant_upserted → o bônus melee sincroniza em tempo real.
      it 'F14.9 — PATCH turn_state com rageAbsorb* (Fúria Absorvente) dispara combatant_upserted com o estado' do
        expect {
          patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}",
                params: { combatant: { turn_state: { rageAbsorbBonus: 3, rageAbsorbRounds: 1 } } },
                headers: player_headers, as: :json
        }.to have_broadcasted_to(stream).with { |data|
          expect(data['event']).to eq('combatant_upserted')
          expect(data['payload']['turn_state']).to eq({ 'rageAbsorbBonus' => 3, 'rageAbsorbRounds' => 1 })
        }
      end

      # F3.7/M4: o resultado de DANO/CURA (hp) do combatente é server-authoritative
      # e sincroniza por combatBridge — o PATCH de hp dispara combatant_upserted com
      # o hp no payload (cobre a Aversão à Magia ÷2 já aplicada antes de escrever hp).
      it 'F3.7/M4 — PATCH hp (dano/cura) dispara combatant_upserted com o hp no payload' do
        expect {
          patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}",
                params: { combatant: { hp_current: 12 } }, headers: dm_headers, as: :json
        }.to have_broadcasted_to(stream).with { |data|
          expect(data['event']).to eq('combatant_upserted')
          expect(data['payload']['hp_current']).to eq(12)
        }
      end
    end

    # ── Forma de Urso (Guerreiro Urso) — SYNC ANCHORS server-side ──────────────
    # O estado durável da forma/agarrão/PV-temp é escrito pelo front via
    # combatBridge (PATCH deste controller) e sincroniza por `combatant_upserted`
    # + PERSISTE em CombatCombatant (sobrevive a reload). Fecha a fronteira de
    # sync que o BDD puro do front NÃO alcança (server-authoritative): F3.15/F3.20
    # (forma), F10.10/F10.15 (agarrão), F14.3/F14.9/F14.11 (Vigor), M1, M4.
    context 'Forma de Urso (Guerreiro Urso) — sync anchors' do
      def stream
        SessionRealtimeChannel.stream_name_for(schedule.id)
      end

      # F3.15/F3.20/M4: bearFormActive + janela de ativação vivem no turn_state do
      # combatente (o DONO do PC muta o próprio). Persiste (round-trip via GET =
      # sobrevive a reload) e dispara combatant_upserted → TODOS os clientes veem a forma.
      it 'F3.15/F3.20/M4 — turn_state bearFormActive persiste, faz round-trip e broadcasta' do
        state = { bearFormActive: true, bearFormActivationRound: 1, bearFormActivationTurnIndex: 0 }
        expected = { 'bearFormActive' => true, 'bearFormActivationRound' => 1, 'bearFormActivationTurnIndex' => 0 }
        expect {
          patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}",
                params: { combatant: { turn_state: state } }, headers: player_headers, as: :json
        }.to have_broadcasted_to(stream).with { |data|
          expect(data['event']).to eq('combatant_upserted')
          expect(data['payload']['turn_state']).to eq(expected)
        }
        expect(combatant.reload.turn_state).to eq(expected)

        get "/api/v1/player/schedules/#{schedule.id}/combat_combatants", headers: player_headers
        row = response.parsed_body['combatants'].find { |c| c['id'] == combatant.id }
        expect(row['turn_state']).to eq(expected) # re-hidrata após reload
      end

      # F10.10/F10.15/M4: o agarrão (grapplingTargetId + CD de fuga) vive no
      # turn_state do URSO — persiste (roundtrip) e broadcasta.
      it 'F10.10/F10.15/M4 — turn_state grapplingTargetId+escapeDC persiste e broadcasta' do
        state = { grapplingTargetId: 'npc-goblin', crushingEmbraceEscapeDC: 15 }
        expected = { 'grapplingTargetId' => 'npc-goblin', 'crushingEmbraceEscapeDC' => 15 }
        expect {
          patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}",
                params: { combatant: { turn_state: state } }, headers: player_headers, as: :json
        }.to have_broadcasted_to(stream).with { |data|
          expect(data['event']).to eq('combatant_upserted')
          expect(data['payload']['turn_state']).to eq(expected)
        }
        expect(combatant.reload.turn_state).to eq(expected)
      end

      # F10.10/M4: as condições grappled + restrained do ALVO são aplicadas pelo
      # jogador do turno (COMBAT_EFFECT_FIELDS) e broadcastam → todos veem o alvo
      # Agarrado/Impedido em tempo real (F10.14 garante que AMBAS são limpas juntas).
      it 'F10.10/M4 — PATCH conditions [grappled, restrained] no alvo broadcasta as duas' do
        victim_npc = create(:combat_npc, schedule: schedule)
        victim = create(:combat_combatant, :npc, combat_state: cs, combatable: victim_npc, position: 1)
        cs.update_column(:current_turn_index, combatant.position) # turno do Urso

        expect {
          patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{victim.id}",
                params: { combatant: { conditions: [{ id: 'grappled', turns_left: 0 }, { id: 'restrained', turns_left: 0 }] } },
                headers: player_headers, as: :json
        }.to have_broadcasted_to(stream).with { |data|
          expect(data['event']).to eq('combatant_upserted')
          ids = data['payload']['conditions'].map { |c| c['id'] }
          expect(ids).to contain_exactly('grappled', 'restrained')
        }
      end

      # F14.3/F14.9/F14.11/M4: os PV temp do Vigor do Urso (2×nível) são aplicados
      # pelo jogador do turno (temp_hp ∈ COMBAT_EFFECT_FIELDS) e sincronizam + persistem.
      it 'F14.3/F14.9/F14.11/M4 — PATCH temp_hp (Vigor) persiste e broadcasta' do
        cs.update_column(:current_turn_index, combatant.position) # turno do Urso

        expect {
          patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}",
                params: { combatant: { temp_hp: 28 } }, headers: player_headers, as: :json
        }.to have_broadcasted_to(stream).with { |data|
          expect(data['event']).to eq('combatant_upserted')
          expect(data['payload']['temp_hp']).to eq(28)
        }
        expect(combatant.reload.temp_hp).to eq(28)
      end

      # M1: um jogador NUNCA consome economia (ação/bônus/reação) de OUTRO player.
      # actions_used ∉ COMBAT_EFFECT_FIELDS → só o DONO do combatente (ou o DM) o muta;
      # mesmo no próprio turno, mutar o actions_used de outro combatente dá 403.
      it 'M1 — jogador NÃO muta actions_used de combatente de OUTRO player (403)' do
        other_user = create(:user, role: player_role)
        other_char = create(:character, user: other_user, group: schedule.group)
        other_combatant = create(:combat_combatant, combat_state: cs, combatable: other_char, position: 2)
        cs.update_column(:current_turn_index, combatant.position) # meu turno

        patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{other_combatant.id}",
              params: { combatant: { actions_used: { reaction: true } } }, headers: player_headers, as: :json

        expect(response).to have_http_status(:forbidden)
        expect(other_combatant.reload.actions_used['reaction']).to be_falsey
      end
    end

    # Efeito de combate (dano/cura) aplicado pelo JOGADOR DONO do combatente do
    # TURNO ATUAL em QUALQUER combatente — habilita poção/ataque/magia do jogador
    # (a regra "curado de 0 volta à batalha" envia a transição de morte derivada).
    context 'efeito de combate do jogador no próprio turno' do
      let!(:npc) { create(:combat_npc, schedule: schedule, hp_current: 0, hp_max: 5) }
      let!(:npc_combatant) do
        create(:combat_combatant, :npc, combat_state: cs, combatable: npc, position: 1, hp_current: 0, hp_max: 5)
      end

      before { cs.update_column(:current_turn_index, combatant.position) } # turno do PC do player

      it 'permite curar um NPC (hp + transição de morte) quando é o turno do jogador' do
        payload = {
          combatant: {
            hp_current: 5, is_dead: false, is_stabilized: false,
            conditions: [], death_saves: { successes: 0, failures: 0 },
          }
        }
        patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{npc_combatant.id}",
              params: payload, headers: player_headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(npc_combatant.reload.hp_current).to eq(5)
      end

      it '403 quando NÃO é o turno do jogador' do
        cs.update_column(:current_turn_index, npc_combatant.position)
        patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{npc_combatant.id}",
              params: { combatant: { hp_current: 5 } }, headers: player_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it '403 quando o jogador do turno tenta mutar campo fora do efeito (name)' do
        patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{npc_combatant.id}",
              params: { combatant: { name: 'Hackeado' } }, headers: player_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    # O jogador precisa resolver o PRÓPRIO teste de resistência quando é ALVO fora do
    # seu turno (ex.: apanha uma área na vez de outro): a resolução mexe no hp dele
    # (auto-dano) + turn_state (limpa o pending). Sem esta liberação dava 403 e o
    # pending nunca resolvia (reload destravava a barra; conjurador preso).
    context 'jogador muta o PRÓPRIO combatente fora do seu turno (resolver o próprio TR)' do
      let!(:npc) { create(:combat_npc, schedule: schedule) }
      let!(:npc_combatant) { create(:combat_combatant, :npc, combat_state: cs, combatable: npc, position: 1) }

      before { cs.update_column(:current_turn_index, npc_combatant.position) } # NÃO é o turno do player

      it 'permite hp + turn_state no PRÓPRIO combatente mesmo fora do seu turno (auto-dano de área)' do
        payload = { combatant: { hp_current: 14, turn_state: { 'afterAoe' => true } } }
        patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}",
              params: payload, headers: player_headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(combatant.reload.hp_current).to eq(14)
      end

      it '403 ao tentar mutar o combatente de OUTRO fora do turno (escopo: só o próprio)' do
        patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{npc_combatant.id}",
              params: { combatant: { hp_current: 3 } }, headers: player_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    # O REATOR de um Ataque de Oportunidade aplica dano no ALVO (mover) — combatente que
    # NÃO é dele e FORA do seu turno. Legítimo quando há uma interação opportunity_attack
    # ATIVA em que o PC do jogador é o REATOR (source_id) e o alvo é o mover.
    context 'jogador aplica dano de REAÇÃO (Ataque de Oportunidade) no alvo' do
      let!(:mover_npc) { create(:combat_npc, schedule: schedule, hp_current: 20, hp_max: 20) }
      let!(:mover) { create(:combat_combatant, :npc, combat_state: cs, combatable: mover_npc, position: 3, hp_current: 20, hp_max: 20) }

      before { cs.update_column(:current_turn_index, mover.position) } # turno do MOVER, não do reator

      def set_oa(source_char_id)
        cs.update!(active_interaction: {
          'kind' => 'opportunity_attack',
          'source_id' => source_char_id.to_s,
          'target_ids' => [],
          'opportunity_attack' => { 'mover_combatant_id' => mover.id.to_s },
        })
      end

      it 'permite hp no ALVO quando o PC do jogador é o REATOR de um AO ativo' do
        set_oa(player_character.id)
        patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{mover.id}",
              params: { combatant: { hp_current: 12 } }, headers: player_headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(mover.reload.hp_current).to eq(12)
      end

      it '403 sem interação de AO ativa' do
        cs.update!(active_interaction: nil)
        patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{mover.id}",
              params: { combatant: { hp_current: 12 } }, headers: player_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it '403 quando o REATOR do AO não é PC do jogador' do
        other_char = create(:character, user: outsider, group: schedule.group)
        set_oa(other_char.id)
        patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{mover.id}",
              params: { combatant: { hp_current: 12 } }, headers: player_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      # REGRESSÃO: o caminho de dano do front SEMPRE anexa turn_state
      # (rageTookDamageSinceLastTurn) ao PATCH ao sofrer dano. A allowlist da reação
      # precisa aceitar turn_state (COMBAT_EFFECT_ON_TURN_FIELDS) — senão o payload REAL
      # do AO (hp_current + temp_hp + turn_state) dava 403 e o dano do reator NÃO subtraía
      # HP no alvo (bug: só passava se, por acaso, viesse hp puro).
      it 'permite o payload REAL do AO (hp_current + temp_hp + turn_state) no ALVO' do
        set_oa(player_character.id)
        patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{mover.id}",
              params: { combatant: { hp_current: 12, temp_hp: 0, turn_state: { 'rageTookDamageSinceLastTurn' => true } } },
              headers: player_headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(mover.reload.hp_current).to eq(12)
        expect(mover.turn_state).to include('rageTookDamageSinceLastTurn' => true)
      end

      it '403 ao tentar actions_used pela via de reação (economia do alvo fica com o alvo)' do
        set_oa(player_character.id)
        patch "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{mover.id}",
              params: { combatant: { hp_current: 12, actions_used: { 'reaction' => true } } },
              headers: player_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'DELETE destroy' do
    it 'deletes the combatant for the DM' do
      combatant = create(:combat_combatant, combat_state: cs, combatable: player_character, position: 0)
      expect {
        delete "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}", headers: dm_headers
      }.to change { CombatCombatant.count }.by(-1)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST reorder' do
    let!(:c0) { create(:combat_combatant, combat_state: cs, combatable: player_character, position: 0, name: 'A') }
    let!(:c1) {
      char2 = create(:character, group: schedule.group, name: 'B-char')
      create(:combat_combatant, combat_state: cs, combatable: char2, position: 1, name: 'B')
    }
    let!(:c2) {
      npc = create(:combat_npc, schedule: schedule)
      create(:combat_combatant, :npc, combat_state: cs, combatable: npc, position: 2, name: 'C')
    }

    it 'reorders atomically (DM)' do
      post "/api/v1/player/schedules/#{schedule.id}/combat_combatants/reorder",
           params: { ordered_combatant_ids: [c2.id, c0.id, c1.id] },
           headers: dm_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(c0.reload.position).to eq(1)
      expect(c1.reload.position).to eq(2)
      expect(c2.reload.position).to eq(0)
    end

    it '422 when ordered list does not cover all combatants' do
      post "/api/v1/player/schedules/#{schedule.id}/combat_combatants/reorder",
           params: { ordered_combatant_ids: [c0.id, c1.id] },
           headers: dm_headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it '403 for Player' do
      post "/api/v1/player/schedules/#{schedule.id}/combat_combatants/reorder",
           params: { ordered_combatant_ids: [c2.id, c0.id, c1.id] },
           headers: player_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST apply_damage' do
    let!(:combatant) {
      create(:combat_combatant, combat_state: cs, combatable: player_character, position: 0,
             hp_current: 20, hp_max: 20, temp_hp: 5)
    }

    it 'applies damage consuming temp_hp first' do
      post "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}/apply_damage",
           params: { amount: 8 }, headers: dm_headers, as: :json

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['combatant']['hp_current']).to eq(17)
      expect(json['combatant']['temp_hp']).to eq(0)
      expect(json['damage_applied']).to eq(8)
      expect(json['concentration_check_required']).to be false
    end

    it 'flags concentration_check_required and computes DC = max(10, dmg/2)' do
      combatant.update!(is_concentrating: true, concentration_spell: 'bless')
      post "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}/apply_damage",
           params: { amount: 30 }, headers: dm_headers, as: :json

      json = response.parsed_body
      expect(json['concentration_check_required']).to be true
      expect(json['concentration_dc']).to eq(15) # max(10, 30/2)
    end

    it 'DC=10 floor for small damage' do
      combatant.update!(is_concentrating: true)
      post "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}/apply_damage",
           params: { amount: 4 }, headers: dm_headers, as: :json

      expect(response.parsed_body['concentration_dc']).to eq(10)
    end

    it '403 for Player' do
      post "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}/apply_damage",
           params: { amount: 5 }, headers: player_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'honra damage_type — alvo imune sofre 0 (mitigação tipada fiada no endpoint)' do
      create(:sheet, character: player_character, hp_current: 20, hp_max: 20,
             metadata: { 'damage_immunities' => ['fogo'] })
      post "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}/apply_damage",
           params: { amount: 12, damage_type: 'fogo' }, headers: dm_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['damage_applied']).to eq(0)
    end
  end

  describe 'POST apply_typed_damage (correlação realtime)' do
    let!(:combatant) do
      create(
        :combat_combatant,
        combat_state: cs,
        combatable: player_character,
        position: 1,
        hp_current: 20,
        hp_max: 20,
      )
    end
    let(:path) do
      "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}/apply_typed_damage"
    end
    let(:damage_params) do
      { parcels: [{ amount: 6, damage_type: 'trovao', magical: true }] }
    end

    it 'propaga commandId/clientId no ACK e no broadcast confirmado' do
      headers = dm_headers.merge(
        'X-Lafiga-Client-Id' => 'cli-dm-desktop',
        'X-Lafiga-Command-Id' => 'cmd-typed-damage-1',
      )
      event_id = nil

      expect do
        post path, params: damage_params, headers: headers, as: :json
      end.to have_broadcasted_to(SessionRealtimeChannel.stream_name_for(schedule.id)).with { |raw|
        event = raw.deep_stringify_keys
        next false unless event['event'] == 'combatant_upserted'

        event_id = event['event_id']
        event['command_id'] == 'cmd-typed-damage-1' &&
          event['client_id'] == 'cli-dm-desktop' &&
          event.dig('payload', 'id') == combatant.id
      }

      expect(response).to have_http_status(:ok)
      expect(combatant.reload.hp_current).to eq(14)
      expect(response.parsed_body['realtime']).to include(
        'commandId' => 'cmd-typed-damage-1',
        'clientId' => 'cli-dm-desktop',
        'eventId' => event_id,
      )
    end

    it 'registra a rejeição quando o dono do alvo resolve o TR fora do próprio turno' do
      attacker = create(:character, user: outsider, group: schedule.group)
      create(:combat_combatant, combat_state: cs, combatable: attacker, position: 0)
      cs.update_column(:current_turn_index, 0)
      headers = player_headers.merge(
        'X-Lafiga-Client-Id' => 'cli-player-phone',
        'X-Lafiga-Command-Id' => 'cmd-pending-save-1',
      )

      expect(Realtime::Telemetry).to receive(:emit).with(hash_including(
        stage: 'command_received',
        command_id: 'cmd-pending-save-1',
        client_id: 'cli-player-phone',
      )).and_call_original
      expect(Realtime::Telemetry).to receive(:emit).with(hash_including(
        stage: 'command_rejected',
        command_id: 'cmd-pending-save-1',
        error_class: 'authorization_failed',
      )).and_call_original

      expect do
        post path, params: damage_params, headers: headers, as: :json
      end.not_to change { combatant.reload.hp_current }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST heal' do
    let!(:combatant) {
      create(:combat_combatant, combat_state: cs, combatable: player_character, position: 0,
             hp_current: 5, hp_max: 20)
    }

    it 'heals the combatant' do
      post "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}/heal",
           params: { amount: 7 }, headers: dm_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['combatant']['hp_current']).to eq(12)
    end
  end

  describe 'POST record_death_save' do
    let!(:combatant) {
      create(:combat_combatant, combat_state: cs, combatable: player_character, position: 0,
             hp_current: 0)
    }

    it 'increments successes and stabilizes on the third' do
      2.times do
        post "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}/record_death_save",
             params: { kind: 'success' }, headers: dm_headers, as: :json
      end
      expect(combatant.reload.is_stabilized).to be false

      post "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}/record_death_save",
           params: { kind: 'success' }, headers: dm_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(combatant.reload.is_stabilized).to be true
    end

    it '422 for unknown kind' do
      post "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}/record_death_save",
           params: { kind: 'critical' }, headers: dm_headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    # Jogador DONO do PC pode gravar o PRÓPRIO teste de morte quando é o turno
    # dele. NPC e fora-do-turno continuam só-DM (espelha efeito de combate).
    context 'jogador gravando o próprio teste de morte no próprio turno' do
      let!(:npc) { create(:combat_npc, schedule: schedule) }
      let!(:npc_combatant) do
        create(:combat_combatant, :npc, combat_state: cs, combatable: npc, position: 1, hp_current: 0)
      end

      it 'permite ao dono do PC gravar o teste de morte no seu próprio turno' do
        cs.update_column(:current_turn_index, combatant.position)
        post "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}/record_death_save",
             params: { kind: 'success' }, headers: player_headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(combatant.reload.death_saves['successes']).to eq(1)
      end

      it '403 quando o jogador tenta gravar o teste de morte de OUTRO combatente (NPC)' do
        cs.update_column(:current_turn_index, combatant.position) # é o turno do PC do player
        post "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{npc_combatant.id}/record_death_save",
             params: { kind: 'failure' }, headers: player_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it '403 quando NÃO é o turno do jogador' do
        cs.update_column(:current_turn_index, npc_combatant.position)
        post "/api/v1/player/schedules/#{schedule.id}/combat_combatants/#{combatant.id}/record_death_save",
             params: { kind: 'success' }, headers: player_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
