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
end
