# frozen_string_literal: true

require 'rails_helper'

# Cobre o ciclo completo da Wiki Sections API:
#   - Public#index (sem auth)
#   - Admin#create / #update / #destroy / #reorder (DM-only)
#   - Built-in: nao removivel; slug imutavel
#   - Player comum: 403 em mutate
RSpec.describe 'Wiki Sections API', type: :request do
  let(:dm_role)     { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:dm)          { create(:user, role: dm_role) }
  let(:player)      { create(:user, role: player_role) }

  let!(:planes) do
    WikiSection.find_or_create_by!(slug: 'planes') do |s|
      s.label = 'Os Planos'
      s.icon_name = 'Globe'
      s.position = 0
      s.built_in = true
    end
  end

  let!(:gods) do
    WikiSection.find_or_create_by!(slug: 'gods') do |s|
      s.label = 'Os Deuses'
      s.icon_name = 'Crown'
      s.position = 1
      s.built_in = true
    end
  end

  describe 'GET /api/v1/public/wiki_sections' do
    it 'retorna todas as secoes ordenadas por position, sem auth' do
      get '/api/v1/public/wiki_sections'
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['wiki_sections']).to be_an(Array)
      slugs = body['wiki_sections'].map { |s| s['slug'] }
      expect(slugs.first(2)).to eq(%w[planes gods])
      payload = body['wiki_sections'].first
      expect(payload).to include('id', 'slug', 'label', 'icon_name', 'position', 'built_in', 'path')
      expect(payload['built_in']).to eq(true)
      expect(payload['path']).to eq('/wiki/planos')
    end
  end

  describe 'POST /api/v1/admin/wiki_sections' do
    let(:valid_payload) do
      { wiki_section: { slug: 'bestiario-local', label: 'Bestiario Local', icon_name: 'Skull' } }
    end

    it 'jogador comum recebe 403' do
      post '/api/v1/admin/wiki_sections', params: valid_payload, as: :json,
           headers: bearer_headers_for(player)
      expect(response).to have_http_status(:forbidden)
    end

    it 'sem token responde 401' do
      post '/api/v1/admin/wiki_sections', params: valid_payload, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'DM cria secao custom com built_in=false e path /wiki/c/<slug>' do
      post '/api/v1/admin/wiki_sections', params: valid_payload, as: :json,
           headers: bearer_headers_for(dm)
      expect(response).to have_http_status(:created)
      payload = response.parsed_body['wiki_section']
      expect(payload['slug']).to eq('bestiario-local')
      expect(payload['built_in']).to eq(false)
      expect(payload['path']).to eq('/wiki/c/bestiario-local')
    end

    it 'rejeita slug duplicado' do
      WikiSection.create!(slug: 'colidir', label: 'X', icon_name: 'Globe', position: 99)
      post '/api/v1/admin/wiki_sections',
           params: { wiki_section: { slug: 'colidir', label: 'Y', icon_name: 'Globe' } },
           as: :json, headers: bearer_headers_for(dm)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rejeita icon_name fora do catalogo' do
      post '/api/v1/admin/wiki_sections',
           params: { wiki_section: { slug: 'desconhecido', label: 'X', icon_name: 'NaoExiste' } },
           as: :json, headers: bearer_headers_for(dm)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH /api/v1/admin/wiki_sections/:id' do
    it 'DM renomeia built-in (label/icon/desc/position aceitos; slug nao muda)' do
      patch "/api/v1/admin/wiki_sections/#{planes.id}",
            params: { wiki_section: { label: 'Os Planos do Cosmo', slug: 'tentou-trocar' } },
            as: :json, headers: bearer_headers_for(dm)
      expect(response).to have_http_status(:ok)
      planes.reload
      expect(planes.label).to eq('Os Planos do Cosmo')
      expect(planes.slug).to eq('planes')
    end
  end

  describe 'DELETE /api/v1/admin/wiki_sections/:id' do
    it 'DM nao consegue destruir built-in (422)' do
      delete "/api/v1/admin/wiki_sections/#{planes.id}",
             headers: bearer_headers_for(dm)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(WikiSection.exists?(planes.id)).to eq(true)
    end

    it 'DM destroi custom (204)' do
      custom = WikiSection.create!(slug: 'pra-deletar', label: 'X', icon_name: 'Globe', position: 50)
      delete "/api/v1/admin/wiki_sections/#{custom.id}", headers: bearer_headers_for(dm)
      expect(response).to have_http_status(:no_content)
      expect(WikiSection.exists?(custom.id)).to eq(false)
    end
  end

  describe 'POST /api/v1/admin/wiki_sections/reorder' do
    it 'reordena por sequencia de slugs' do
      post '/api/v1/admin/wiki_sections/reorder',
           params: { order: %w[gods planes] }, as: :json,
           headers: bearer_headers_for(dm)
      expect(response).to have_http_status(:ok)
      slugs = response.parsed_body['wiki_sections'].map { |s| s['slug'] }
      expect(slugs.first(2)).to eq(%w[gods planes])
    end

    it '422 quando algum slug nao existe' do
      post '/api/v1/admin/wiki_sections/reorder',
           params: { order: %w[gods inexistente] }, as: :json,
           headers: bearer_headers_for(dm)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it '422 com order vazio' do
      post '/api/v1/admin/wiki_sections/reorder',
           params: { order: [] }, as: :json,
           headers: bearer_headers_for(dm)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'jogador comum recebe 403' do
      post '/api/v1/admin/wiki_sections/reorder',
           params: { order: %w[planes gods] }, as: :json,
           headers: bearer_headers_for(player)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
