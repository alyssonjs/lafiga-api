# frozen_string_literal: true

require 'rails_helper'

# BDD — Loop 3: GET /api/v1/public/class_rules inclui klasses.rules
RSpec.describe 'Api::V1::Public::ClassRules', type: :request do
  describe 'GET /api/v1/public/class_rules' do
    it 'B6.1 — responde 200 e inclui class_rules + dictionaries' do
      get '/api/v1/public/class_rules'
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['class_rules']).to be_a(Hash)
      expect(json['dictionaries']).to be_a(Hash)
    end

    it 'B6.2 — inclui chave de classe apenas em klasses.rules' do
      create(
        :klass,
        api_index: 'loop3_public_index',
        rules: {
          id: 'loop3_public_index',
          name: 'Classe Só Tabela',
          hit_die: 'd8',
          primary_abilities: %w[INT]
        }
      )
      get '/api/v1/public/class_rules'
      expect(response).to have_http_status(:ok)
      cr = JSON.parse(response.body)['class_rules']
      expect(cr).to be_a(Hash)
      expect(cr['loop3_public_index']['name']).to eq('Classe Só Tabela')
      expect(cr['loop3_public_index']['hit_die']).to eq('d8')
    end
  end
end
