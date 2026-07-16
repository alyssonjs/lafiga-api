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

      it '403 quando o jogador tenta mutar turn_state de combatente de OUTRO (NPC), mesmo no próprio turno' do
        npc = create(:combat_npc, schedule: schedule)
        npc_combatant = create(:combat_combatant, :npc, combat_state: cs, combatable: npc, position: 1)
        cs.update_column(:current_turn_index, combatant.position) # turno do PC do player

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
