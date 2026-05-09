# frozen_string_literal: true

require 'rails_helper'

# BDD — `GET /api/v1/public/skills` (catálogo canônico das 18 perícias PHB).
#
# Este endpoint é a fonte que o FRONT consome (Fase A da centralização) em
# vez de manter `ABILITY_BLOCKS` hardcoded em `types.ts`. Asserta o contrato:
#   - 200 + envelope `{ skills: [...], meta: {...} }`
#   - cada skill tem `id`/`name`/`ability` non-empty
#   - `:id` no `show` resolve por slug E por nome (case-insensitive)
RSpec.describe 'Api::V1::Public::Skills', type: :request do
  before { SkillsCatalog.reload! }

  describe 'GET /api/v1/public/skills' do
    it 'responde 200 com 18 skills' do
      get '/api/v1/public/skills'
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['skills']).to be_an(Array)
      expect(json['skills'].length).to eq(18),
        "PHB 5e tem 18 skills; endpoint devolveu #{json['skills'].length}"
    end

    it 'envelope inclui meta { total, source }' do
      get '/api/v1/public/skills'
      json = JSON.parse(response.body)
      expect(json['meta']).to include('total' => 18, 'source' => 'config/skills.yml')
    end

    it 'cada skill tem id, name e ability não-vazios' do
      get '/api/v1/public/skills'
      json = JSON.parse(response.body)
      bad = json['skills'].reject { |s| s['id'].present? && s['name'].present? && s['ability'].present? }
      expect(bad).to be_empty, "skills com campos vazios: #{bad.inspect}"
    end

    it 'ability é STR/DEX/CON/INT/WIS/CHA' do
      get '/api/v1/public/skills'
      json = JSON.parse(response.body)
      bad = json['skills'].reject { |s| %w[STR DEX CON INT WIS CHA].include?(s['ability']) }
      expect(bad).to be_empty, "skills com ability inválido: #{bad.inspect}"
    end

    it 'inclui as canônicas PT-BR (Atletismo, Arcanismo, Lidar com Animais)' do
      get '/api/v1/public/skills'
      names = JSON.parse(response.body)['skills'].map { |s| s['name'] }
      expect(names).to include('Atletismo', 'Arcanismo', 'Lidar com Animais', 'Prestidigitação', 'Persuasão')
    end

    it 'NÃO inclui nomes EN (proteção contra regressão "Arcana" do Sage)' do
      get '/api/v1/public/skills'
      names = JSON.parse(response.body)['skills'].map { |s| s['name'] }
      bad_en_names = %w[Arcana Athletics Stealth Persuasion Perception]
      bleed = bad_en_names & names
      expect(bleed).to be_empty,
        "Endpoint vazou nomes EN: #{bleed.inspect}. Catálogo deve ser estritamente PT-BR canônico."
    end
  end

  describe 'GET /api/v1/public/skills/:id' do
    it 'resolve por slug (athletics → Atletismo)' do
      get '/api/v1/public/skills/athletics'
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['skill']).to include('id' => 'athletics', 'name' => 'Atletismo', 'ability' => 'STR')
    end

    it 'resolve por nome PT-BR (Atletismo)' do
      get '/api/v1/public/skills/Atletismo'
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['skill']['id']).to eq('athletics')
    end

    it 'resolve case-insensitive (atletismo)' do
      get '/api/v1/public/skills/atletismo'
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['skill']['id']).to eq('athletics')
    end

    it 'retorna 404 quando id desconhecido' do
      get '/api/v1/public/skills/voar'
      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)['error']).to be_present
    end
  end
end
