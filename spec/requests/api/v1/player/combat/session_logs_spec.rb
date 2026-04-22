# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Player::Combat::SessionLogsController', type: :request do
  let(:dm_role)     { Role.find_or_create_by!(name: 'DM') }
  let(:player_role) { Role.find_or_create_by!(name: 'Player') }

  let(:dm)        { create(:user, role: dm_role) }
  let(:player)    { create(:user, role: player_role, name: 'Alice') }
  let(:outsider)  { create(:user, role: player_role) }

  let(:schedule)  { create(:schedule) }
  let!(:player_character) { create(:character, user: player, group: schedule.group, name: 'Aelarion') }

  let(:dm_headers)        { bearer_headers_for(dm) }
  let(:player_headers)    { bearer_headers_for(player) }
  let(:outsider_headers)  { bearer_headers_for(outsider) }

  describe 'GET index' do
    it 'returns logs newest first' do
      old_log = create(:session_log, schedule: schedule, message: 'old',  posted_at: 2.minutes.ago)
      new_log = create(:session_log, schedule: schedule, message: 'new',  posted_at: 1.second.ago)

      get "/api/v1/player/schedules/#{schedule.id}/session_logs", headers: player_headers
      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['logs'].pluck('id')
      expect(ids).to eq([new_log.id, old_log.id])
    end

    it 'filters by ?kind' do
      narrative = create(:session_log, schedule: schedule, kind: :narrative, message: 'narr')
      roll      = create(:session_log, schedule: schedule, kind: :roll,
                         message: 'rolled',
                         roll_result: { 'expression' => '1d20+5', 'total' => 17 })

      get "/api/v1/player/schedules/#{schedule.id}/session_logs?kind=roll", headers: player_headers
      ids = response.parsed_body['logs'].pluck('id')
      expect(ids).to contain_exactly(roll.id)
    end

    it 'filters by ?since' do
      old_log = create(:session_log, schedule: schedule, message: 'old', created_at: 2.hours.ago, posted_at: 2.hours.ago)
      new_log = create(:session_log, schedule: schedule, message: 'fresh')

      get "/api/v1/player/schedules/#{schedule.id}/session_logs?since=#{1.hour.ago.iso8601}",
          headers: player_headers
      ids = response.parsed_body['logs'].pluck('id')
      expect(ids).to contain_exactly(new_log.id)
    end

    it '200 for outsider (hub read)' do
      get "/api/v1/player/schedules/#{schedule.id}/session_logs", headers: outsider_headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST create' do
    it 'creates a narrative log for a member with default actor=character name' do
      post "/api/v1/player/schedules/#{schedule.id}/session_logs",
           params: { log: { kind: 'narrative', message: 'Entrei na taverna.' } },
           headers: player_headers, as: :json

      expect(response).to have_http_status(:created)
      json = response.parsed_body['log']
      expect(json).to include('kind' => 'narrative', 'message' => 'Entrei na taverna.', 'actor' => 'Aelarion')
    end

    it 'creates a roll log with roll_result payload' do
      post "/api/v1/player/schedules/#{schedule.id}/session_logs",
           params: { log: { kind: 'roll', message: 'Ataque!', roll_result: { expression: '1d20+5', total: 23 } } },
           headers: player_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['log']['roll_result']).to include('expression' => '1d20+5', 'total' => 23)
    end

    it '422 when message is missing' do
      post "/api/v1/player/schedules/#{schedule.id}/session_logs",
           params: { log: { kind: 'narrative' } },
           headers: player_headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it '422 when roll_result is malformed (no total)' do
      post "/api/v1/player/schedules/#{schedule.id}/session_logs",
           params: { log: { kind: 'roll', message: 'X', roll_result: { expression: '1d20' } } },
           headers: player_headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'allows DM to create logs (default actor falls back to user.name)' do
      dm.update!(name: 'Carol DM')
      post "/api/v1/player/schedules/#{schedule.id}/session_logs",
           params: { log: { kind: 'note', message: 'Anotação do mestre.' } },
           headers: dm_headers, as: :json
      expect(response).to have_http_status(:created)
      expect(response.parsed_body['log']['actor']).to eq('Carol DM')
    end

    it '403 for outsider' do
      post "/api/v1/player/schedules/#{schedule.id}/session_logs",
           params: { log: { kind: 'narrative', message: 'hi' } },
           headers: outsider_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
