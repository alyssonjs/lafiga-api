# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Player::Combat::CombatNpcsController', type: :request do
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

  describe 'GET index' do
    it 'lists alive NPCs by default' do
      alive   = create(:combat_npc, schedule: schedule, name: 'Goblin')
      defeated = create(:combat_npc, schedule: schedule, name: 'Orc', defeated_at: 1.minute.ago)

      get "/api/v1/player/schedules/#{schedule.id}/combat_npcs", headers: player_headers
      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['npcs'].pluck('id')
      expect(ids).to include(alive.id)
      expect(ids).not_to include(defeated.id)
    end

    it 'includes defeated when ?include_defeated=1' do
      create(:combat_npc, schedule: schedule, name: 'Orc', defeated_at: 1.minute.ago)
      get "/api/v1/player/schedules/#{schedule.id}/combat_npcs?include_defeated=1", headers: player_headers
      expect(response.parsed_body['npcs'].size).to eq(1)
    end

    it '200 for outsider (hub read)' do
      get "/api/v1/player/schedules/#{schedule.id}/combat_npcs", headers: outsider_headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST create' do
    let(:payload) {
      {
        npc: {
          name: 'Goblin Sneak',
          hp_current: 7, hp_max: 7, ac: 13,
          stats: { str: 8, dex: 14, con: 10, int: 10, wis: 8, cha: 8 },
          attacks: [{ name: 'Scimitar', attack_bonus: 4, damage_dice: '1d6+2', damage_type: 'slashing' }],
        }
      }
    }

    it 'creates an NPC for the DM' do
      expect {
        post "/api/v1/player/schedules/#{schedule.id}/combat_npcs",
             params: payload, headers: dm_headers, as: :json
      }.to change { schedule.combat_npcs.count }.by(1)
      expect(response).to have_http_status(:created)
      json = response.parsed_body['npc']
      expect(json['name']).to eq('Goblin Sneak')
      expect(json['stats']).to include('dex' => 14)
      expect(json['attacks'].first['name']).to eq('Scimitar')
    end

    it '403 for Player' do
      post "/api/v1/player/schedules/#{schedule.id}/combat_npcs",
           params: payload, headers: player_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it '422 with invalid stats key' do
      bad = payload.deep_dup
      bad[:npc][:stats] = { foo: 1 }
      post "/api/v1/player/schedules/#{schedule.id}/combat_npcs",
           params: bad, headers: dm_headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH update' do
    let!(:npc) { create(:combat_npc, schedule: schedule, hp_current: 7, hp_max: 7) }

    it 'updates HP for the DM' do
      patch "/api/v1/player/schedules/#{schedule.id}/combat_npcs/#{npc.id}",
            params: { npc: { hp_current: 3 } }, headers: dm_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(npc.reload.hp_current).to eq(3)
    end
  end

  describe 'POST defeat / revive' do
    let!(:npc) { create(:combat_npc, schedule: schedule) }

    it 'defeats and revives' do
      post "/api/v1/player/schedules/#{schedule.id}/combat_npcs/#{npc.id}/defeat", headers: dm_headers
      expect(response).to have_http_status(:ok)
      expect(npc.reload.defeated_at).to be_present

      post "/api/v1/player/schedules/#{schedule.id}/combat_npcs/#{npc.id}/revive", headers: dm_headers
      expect(npc.reload.defeated_at).to be_nil
    end

    it '403 for Player on defeat' do
      post "/api/v1/player/schedules/#{schedule.id}/combat_npcs/#{npc.id}/defeat", headers: player_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'DELETE destroy' do
    it 'deletes NPC and its combatants (dependent: :destroy)' do
      npc = create(:combat_npc, schedule: schedule)
      cs = create(:combat_state, schedule: schedule)
      create(:combat_combatant, :npc, combat_state: cs, combatable: npc, position: 0)

      expect {
        delete "/api/v1/player/schedules/#{schedule.id}/combat_npcs/#{npc.id}", headers: dm_headers
      }.to change { CombatNpc.count }.by(-1)
       .and change { CombatCombatant.count }.by(-1)
    end
  end
end
