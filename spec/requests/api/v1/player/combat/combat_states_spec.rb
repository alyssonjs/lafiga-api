# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Player::Combat::CombatStatesController', type: :request do
  let(:dm_role)     { Role.find_or_create_by!(name: 'DM') }
  let(:player_role) { Role.find_or_create_by!(name: 'Player') }

  let(:dm)        { create(:user, role: dm_role) }
  let(:player)    { create(:user, role: player_role) }
  let(:player2)   { create(:user, role: player_role) }
  let(:outsider)  { create(:user, role: player_role) }

  let(:schedule)  { create(:schedule) }
  let!(:player_character) { create(:character, user: player, group: schedule.group) }
  let!(:player2_character) { create(:character, user: player2, group: schedule.group) }

  let(:dm_headers)        { bearer_headers_for(dm) }
  let(:player_headers)    { bearer_headers_for(player) }
  let(:player2_headers)   { bearer_headers_for(player2) }
  let(:outsider_headers)  { bearer_headers_for(outsider) }

  describe 'GET /api/v1/player/schedules/:schedule_id/combat_state' do
    it 'returns the existing combat_state for a member of the group' do
      cs = create(:combat_state, schedule: schedule, active: true, round: 2, started_at: 1.minute.ago)
      get "/api/v1/player/schedules/#{schedule.id}/combat_state", headers: player_headers
      expect(response).to have_http_status(:ok)
      json = response.parsed_body['combat_state']
      expect(json['id']).to eq(cs.id)
      expect(json['active']).to be true
      expect(json['round']).to eq(2)
    end

    it 'returns null combat_state when none exists (not 404)' do
      get "/api/v1/player/schedules/#{schedule.id}/combat_state", headers: player_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['combat_state']).to be_nil
    end

    it 'returns 200 for the DM (site-wide access)' do
      create(:combat_state, schedule: schedule)
      get "/api/v1/player/schedules/#{schedule.id}/combat_state", headers: dm_headers
      expect(response).to have_http_status(:ok)
    end

    it 'returns 200 for an outsider (hub read — no character in the group)' do
      cs = create(:combat_state, schedule: schedule, active: true, round: 1)
      get "/api/v1/player/schedules/#{schedule.id}/combat_state", headers: outsider_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['combat_state']['id']).to eq(cs.id)
    end

    it 'returns 404 when the schedule does not exist' do
      get "/api/v1/player/schedules/999999/combat_state", headers: dm_headers
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 401 without auth' do
      get "/api/v1/player/schedules/#{schedule.id}/combat_state"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST :begin' do
    it 'creates and activates a combat_state when called by the DM' do
      expect {
        post "/api/v1/player/schedules/#{schedule.id}/combat_state/begin", headers: dm_headers
      }.to change { schedule.reload.combat_state }.from(nil)

      expect(response).to have_http_status(:ok)
      cs = schedule.reload.combat_state
      expect(cs).to have_attributes(active: true, round: 1, current_turn_index: 0)
    end

    it 'is idempotent for the DM (no extra row)' do
      create(:combat_state, schedule: schedule, active: true, round: 4, started_at: 1.hour.ago)
      expect {
        post "/api/v1/player/schedules/#{schedule.id}/combat_state/begin", headers: dm_headers
      }.not_to change { CombatState.count }
      expect(response).to have_http_status(:ok)
    end

    it 'returns 403 when called by a Player who is not the campaign owner' do
      post "/api/v1/player/schedules/#{schedule.id}/combat_state/begin", headers: player_headers
      expect(response).to have_http_status(:forbidden)
      expect(schedule.reload.combat_state).to be_nil
    end

    it 'allows the campaign owner (dm_user_id) with Player role to begin combat' do
      schedule.group.update!(dm_user_id: player.id)
      expect {
        post "/api/v1/player/schedules/#{schedule.id}/combat_state/begin", headers: player_headers
      }.to change { schedule.reload.combat_state }.from(nil)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST :finish' do
    it 'deactivates and stamps ended_at' do
      cs = create(:combat_state, schedule: schedule, active: true, round: 3, started_at: 1.hour.ago)
      post "/api/v1/player/schedules/#{schedule.id}/combat_state/finish", headers: dm_headers
      expect(response).to have_http_status(:ok)
      expect(cs.reload.active).to be false
      expect(cs.ended_at).to be_present
    end

    it '422 when there is no combat_state yet' do
      post "/api/v1/player/schedules/#{schedule.id}/combat_state/finish", headers: dm_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it '403 for a member who is not the campaign owner' do
      create(:combat_state, schedule: schedule, active: true, round: 1)
      post "/api/v1/player/schedules/#{schedule.id}/combat_state/finish", headers: player_headers
      expect(response).to have_http_status(:forbidden)
    end

    it 'allows the campaign owner to finish combat' do
      schedule.group.update!(dm_user_id: player.id)
      cs = create(:combat_state, schedule: schedule, active: true, round: 1, started_at: 1.hour.ago)
      post "/api/v1/player/schedules/#{schedule.id}/combat_state/finish", headers: player_headers
      expect(response).to have_http_status(:ok)
      expect(cs.reload.active).to be false
    end
  end

  describe 'POST :advance_turn' do
    let!(:cs) { create(:combat_state, schedule: schedule, active: true, round: 1, current_turn_index: 0) }

    before do
      create(:combat_combatant, combat_state: cs, combatable: player_character, position: 0)
      npc = create(:combat_npc, schedule: schedule)
      create(:combat_combatant, :npc, combat_state: cs, combatable: npc, position: 1)
    end

    it 'advances the turn for the DM' do
      post "/api/v1/player/schedules/#{schedule.id}/combat_state/advance_turn", headers: dm_headers
      expect(response).to have_http_status(:ok)
      expect(cs.reload.current_turn_index).to eq(1)
    end

    it 'broadcasts state_changed and combatant_upserted on advance' do
      envelopes = []
      allow(ActionCable.server).to receive(:broadcast).and_wrap_original do |m, stream_name, data|
        envelopes << data.deep_stringify_keys
        m.call(stream_name, data)
      end
      post "/api/v1/player/schedules/#{schedule.id}/combat_state/advance_turn", headers: dm_headers
      expect(response).to have_http_status(:ok)
      types = envelopes.pluck('event')
      expect(types).to include('state_changed')
      expect(types).to include('combatant_upserted')
      st = envelopes.find { |h| h['event'] == 'state_changed' }
      expect(st['payload']['current_turn_index']).to eq(1)
    end

    it '422 when there is no combat_state' do
      cs.destroy!
      post "/api/v1/player/schedules/#{schedule.id}/combat_state/advance_turn", headers: dm_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'allows the owner of the active PC to advance turn (Passar Vez)' do
      post "/api/v1/player/schedules/#{schedule.id}/combat_state/advance_turn", headers: player_headers
      expect(response).to have_http_status(:ok)
      expect(cs.reload.current_turn_index).to eq(1)
    end

    it '403 for a member whose PC is not the current combatant' do
      post "/api/v1/player/schedules/#{schedule.id}/combat_state/advance_turn", headers: player2_headers
      expect(response).to have_http_status(:forbidden)
      expect(cs.reload.current_turn_index).to eq(0)
    end

    it '422 quando algum combatente vivo ainda nao tem iniciativa' do
      cs.combat_combatants.find_by!(combatable: player_character).update_column(:initiative, nil)
      post "/api/v1/player/schedules/#{schedule.id}/combat_state/advance_turn", headers: dm_headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error'].to_s).to include('iniciativas')
    end
  end

  describe 'POST :set_round' do
    let!(:cs) { create(:combat_state, schedule: schedule, active: true, round: 3) }

    it 'updates the round when called by the DM' do
      post "/api/v1/player/schedules/#{schedule.id}/combat_state/set_round",
           params: { round: 7 }, headers: dm_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(cs.reload.round).to eq(7)
    end

    it '422 when round is invalid for active combat (round=0)' do
      post "/api/v1/player/schedules/#{schedule.id}/combat_state/set_round",
           params: { round: 0 }, headers: dm_headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it '403 for a member who is not the campaign owner' do
      post "/api/v1/player/schedules/#{schedule.id}/combat_state/set_round",
           params: { round: 7 }, headers: player_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'allows the campaign owner to set round' do
      schedule.group.update!(dm_user_id: player.id)
      post "/api/v1/player/schedules/#{schedule.id}/combat_state/set_round",
           params: { round: 7 }, headers: player_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(cs.reload.round).to eq(7)
    end
  end

  describe 'PUT :update_movement_ledger' do
    let!(:cs) { create(:combat_state, schedule: schedule, active: true, round: 1, current_turn_index: 0) }
    let!(:combatant_pc) { create(:combat_combatant, combat_state: cs, combatable: player_character, position: 0) }

    let(:valid_entries) do
      [
        { 'kind' => 'manual', 'ft' => 5.0 },
        { 'kind' => 'map', 'ft' => 10.0, 'tokenId' => 'tok-1', 'prevCol' => 2, 'prevRow' => 3 }
      ]
    end

    it 'persists and returns movement_ledger for the DM' do
      put "/api/v1/player/schedules/#{schedule.id}/combat_state/update_movement_ledger",
          params: { entries: valid_entries }, headers: dm_headers, as: :json
      expect(response).to have_http_status(:ok)
      json = response.parsed_body['combat_state']
      expect(json['movement_ledger'].size).to eq(2)
      expect(cs.reload.movement_ledger).to be_a(Array)
    end

    it 'allows the player whose turn is the active PC' do
      put "/api/v1/player/schedules/#{schedule.id}/combat_state/update_movement_ledger",
          params: { entries: [{ 'kind' => 'manual', 'ft' => 2.0 }] },
          headers: player_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['combat_state']['movement_ledger'].first['ft']).to eq(2.0)
    end

    it '403 for a player not on the active turn' do
      create(:combat_combatant, combat_state: cs, combatable: create(:character, user: player2, group: schedule.group), position: 1)
      cs.update_column(:current_turn_index, 1)
      put "/api/v1/player/schedules/#{schedule.id}/combat_state/update_movement_ledger",
          params: { entries: valid_entries }, headers: player_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it '422 for invalid entries' do
      put "/api/v1/player/schedules/#{schedule.id}/combat_state/update_movement_ledger",
          params: { entries: [{ 'kind' => 'map', 'ft' => 1 }] },
          headers: dm_headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
