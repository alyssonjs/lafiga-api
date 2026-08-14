# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Player::SessionFeedItemsController', type: :request do
  let(:player_role) { Role.find_or_create_by!(name: 'Player') }
  let(:player)      { create(:user, role: player_role) }
  let(:headers)     { bearer_headers_for(player) }
  let(:schedule)    { create(:schedule) }

  describe 'GET index' do
    it 'devolve items mais recentes primeiro com meta' do
      create(:session_feed_item, schedule: schedule, posted_at: 5.minutes.ago, client_id: 'old-msg')
      create(:session_feed_item, schedule: schedule, posted_at: 1.minute.ago,  client_id: 'new-msg')

      get "/api/v1/player/schedules/#{schedule.id}/session_feed_items", headers: headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      ids = body['items'].map { |x| x['id'] }
      expect(ids).to eq(%w[new-msg old-msg])
      expect(body['meta']['count']).to eq(2)
      expect(body['meta']['has_more']).to be(false)
    end

    it 'limita pelo parâmetro limit e devolve next_cursor quando há mais' do
      6.times do |i|
        create(:session_feed_item,
               schedule: schedule,
               posted_at: i.minutes.ago,
               client_id: "msg-#{i}")
      end

      get "/api/v1/player/schedules/#{schedule.id}/session_feed_items?limit=3", headers: headers
      body = response.parsed_body
      expect(body['items'].size).to eq(3)
      expect(body['meta']['has_more']).to be(true)
      expect(body['meta']['next_cursor']).to include('before', 'before_id')
    end

    it 'pagina com cursor before/before_id' do
      now = Time.current
      a = create(:session_feed_item, schedule: schedule, posted_at: now - 1.second,  client_id: 'a')
      b = create(:session_feed_item, schedule: schedule, posted_at: now - 5.seconds, client_id: 'b')
      c = create(:session_feed_item, schedule: schedule, posted_at: now - 10.seconds, client_id: 'c')

      get "/api/v1/player/schedules/#{schedule.id}/session_feed_items?limit=1", headers: headers
      cursor = response.parsed_body['meta']['next_cursor']
      expect(cursor['before']).to be_present

      get "/api/v1/player/schedules/#{schedule.id}/session_feed_items?limit=1&before=#{CGI.escape(cursor['before'])}&before_id=#{cursor['before_id']}",
          headers: headers
      ids = response.parsed_body['items'].map { |x| x['id'] }
      expect(ids).to eq(['b'])
    end

    it 'aceita schedule_id no formato api-NN' do
      create(:session_feed_item, schedule: schedule, posted_at: 1.minute.ago, client_id: 'x')
      get "/api/v1/player/schedules/api-#{schedule.id}/session_feed_items", headers: headers
      expect(response).to have_http_status(:ok)
    end

    it 'devolve 404 para schedule inexistente' do
      get "/api/v1/player/schedules/999999/session_feed_items", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it 'requer autenticação' do
      get "/api/v1/player/schedules/#{schedule.id}/session_feed_items"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST create' do
    let(:roll) do
      {
        kind: 'roll', id: 'roll-http-1', rollGroupId: 'rg-http-1',
        timestamp: 1_700_000_000_000, revealAt: 1_700_000_001_650,
        sessionId: schedule.id.to_s, playerName: 'Lira', characterName: 'Lira',
        senderRole: 'player', type: 'attack', label: 'Lira → alvo · Arco',
        total: 17, breakdown: '13 + 4 = 17', attackHitOutcome: 'pending',
      }
    end

    it 'persiste antes de transmitir e devolve ACK correlacionado' do
      expect do
        post "/api/v1/player/schedules/#{schedule.id}/session_feed_items",
             params: { item: roll },
             headers: headers.merge(
               'X-Lafiga-Client-Id' => 'cli-lira-browser',
               'X-Lafiga-Command-Id' => 'rg-http-1',
             ),
             as: :json
      end.to have_broadcasted_to(SessionFeedChannel.stream_name_for(schedule.id)).with(
        a_hash_including(
          'kind' => 'roll', 'id' => 'roll-http-1', 'total' => 17,
          'commandId' => 'rg-http-1', 'clientId' => 'cli-lira-browser',
        ),
      )

      expect(response).to have_http_status(:ok), -> { response.body }
      stored = SessionFeedItem.find_by!(schedule: schedule, client_id: 'roll-http-1')
      expect(stored.payload).to include('total' => 17, 'revealAt' => 1_700_000_001_650)
      expect(response.parsed_body.dig('realtime', 'commandId')).to eq('rg-http-1')
    end

    it 'é idempotente e mantém o primeiro total quando duas abas repetem o id' do
      post "/api/v1/player/schedules/#{schedule.id}/session_feed_items",
           params: { item: roll }, headers: headers, as: :json
      expect(response).to have_http_status(:ok), -> { response.body }

      post "/api/v1/player/schedules/#{schedule.id}/session_feed_items",
           params: { item: roll.merge(total: 2, breakdown: 'retry obsoleto') },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:ok), -> { response.body }
      expect(response.parsed_body.dig('item', 'total')).to eq(17)
      expect(SessionFeedItem.where(schedule: schedule, client_id: 'roll-http-1').count).to eq(1)
    end

    it 'rejeita payload que não é uma rolagem válida' do
      post "/api/v1/player/schedules/#{schedule.id}/session_feed_items",
           params: { item: { kind: 'chat', id: 'x' } },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(SessionFeedItem.where(schedule: schedule)).to be_empty
    end
  end
end
