# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Public::Monsters', type: :request do
  let!(:goblin) do
    Monster.create!(slug: 'mon-goblin', name: 'Goblin', source: 'srd',
                    payload: { 'type' => 'Humanoide', 'cr' => '1/4', 'xp' => 50 })
  end
  let!(:dragon) do
    Monster.create!(slug: 'mon-dragon', name: 'Dragao Vermelho', source: 'srd',
                    payload: { 'type' => 'Dragao', 'cr' => '17', 'xp' => 18000 })
  end

  describe 'GET /api/v1/public/monsters' do
    it 'lista sem auth' do
      get '/api/v1/public/monsters'
      expect(response).to have_http_status(:ok)
      slugs = response.parsed_body['monsters'].map { |m| m['id'] }
      expect(slugs).to include('mon-goblin', 'mon-dragon')
    end

    it 'filtra por type' do
      get '/api/v1/public/monsters', params: { type: 'Dragao' }
      slugs = response.parsed_body['monsters'].map { |m| m['id'] }
      expect(slugs).to eq(['mon-dragon'])
    end

    it 'filtra por cr_min' do
      get '/api/v1/public/monsters', params: { cr_min: 5 }
      slugs = response.parsed_body['monsters'].map { |m| m['id'] }
      expect(slugs).to eq(['mon-dragon'])
    end

    it 'busca por nome (q)' do
      get '/api/v1/public/monsters', params: { q: 'goblin' }
      slugs = response.parsed_body['monsters'].map { |m| m['id'] }
      expect(slugs).to eq(['mon-goblin'])
    end
  end

  describe 'GET /api/v1/public/monsters/:id' do
    it 'busca por slug' do
      get "/api/v1/public/monsters/#{goblin.slug}"
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('monster', 'name')).to eq('Goblin')
    end

    it 'retorna 404 para slug inexistente' do
      get '/api/v1/public/monsters/mon-inexistente'
      expect(response).to have_http_status(:not_found)
    end
  end
end
