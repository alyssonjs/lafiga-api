# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::Klasses', type: :request do
  let(:admin_role)  { Role.find_by(name: 'Admin')  || create(:role, name: 'Admin') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:admin)       { create(:user, role: admin_role) }
  let(:player)      { create(:user, role: player_role) }
  let(:headers)     { bearer_headers_for(admin).merge('Content-Type' => 'application/json') }

  describe 'GET /api/v1/admin/klasses' do
    let!(:cleric) { create(:klass, name: 'Clerigo', api_index: 'cleric_spec', hit_die: 8) }

    it 'requer DM/Admin' do
      get '/api/v1/admin/klasses', headers: bearer_headers_for(player)
      # `authorize_site_wide_dm` rejeita Player com 403; `authorize_request`
      # aceita login mas o gate de DM é o que importa.
      expect(response.status).to be_in([401, 403])
    end

    it 'lista classes para Admin' do
      get '/api/v1/admin/klasses', headers: headers
      expect(response).to have_http_status(:ok)
      names = response.parsed_body['klasses'].map { |k| k['name'] }
      expect(names).to include('Clerigo')
    end
  end

  describe 'POST /api/v1/admin/klasses' do
    let(:payload) do
      {
        klass: {
          name: 'Bruxo',
          api_index: "bruxo_#{SecureRandom.hex(4)}",
          hit_die: 8,
          spellcasting_ability: 'Carisma',
          primary_ability: 'Carisma',
          description: '<p>Conjurador pactuário.</p>',
          saving_throws: %w[Sabedoria Carisma],
          subclass_level: 1,
        },
      }
    end

    it 'cria classe com todos os novos campos (description / primary_ability / saving_throws)' do
      expect {
        post '/api/v1/admin/klasses', params: payload.to_json, headers: headers
      }.to change(Klass, :count).by(1)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      # Envelope `{ klass: ... }` (alinhado com `update`/`show`).
      expect(body).to have_key('klass')
      expect(body['klass']['name']).to eq('Bruxo')
      expect(body['klass']['description']).to include('Conjurador')
      expect(body['klass']['primary_ability']).to eq('Carisma')
      expect(body['klass']['saving_throws']).to eq(%w[Sabedoria Carisma])
    end

    it 'rejeita Player com 403/401' do
      post '/api/v1/admin/klasses', params: payload.to_json,
                                    headers: bearer_headers_for(player).merge('Content-Type' => 'application/json')
      expect(response.status).to be_in([401, 403])
    end

    it 'retorna 422 quando name está vazio' do
      bad = payload.deep_merge(klass: { name: '' })
      post '/api/v1/admin/klasses', params: bad.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors']).to be_present
    end
  end

  describe 'PATCH /api/v1/admin/klasses/:id' do
    let!(:klass) { create(:klass, name: 'Antigo', hit_die: 6) }

    it 'atualiza name + hit_die + saving_throws + description (regressão guard do bug do modal)' do
      # Bug original: o modal "Editar Classe" coletava esses campos mas
      # o `klass_params` os filtrava silenciosamente. Após a migration
      # `add_description_and_metadata_to_klasses` + permit ampliado, todos
      # devem persistir.
      patch "/api/v1/admin/klasses/#{klass.id}", params: {
        klass: {
          name: 'Atualizado',
          hit_die: 10,
          saving_throws: %w[Forca Constituicao],
          description: '<p>Novo</p>',
          primary_ability: 'Forca',
        },
      }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      klass.reload
      expect(klass.name).to eq('Atualizado')
      expect(klass.hit_die).to eq(10)
      expect(klass.saving_throws).to eq(%w[Forca Constituicao])
      expect(klass.description).to include('Novo')
      expect(klass.primary_ability).to eq('Forca')
    end

    it 'persiste short_description (tagline exibida no header do painel)' do
      # Coluna `short_description` (migration `add_short_description_to_klasses`):
      # tagline curta, exibida no cabecalho do `ClassDetailPanel` abaixo da
      # linha de stats. Distinta de `description` (rich-text na aba Historia).
      patch "/api/v1/admin/klasses/#{klass.id}", params: {
        klass: { short_description: 'Guerreiro berserker movido pela fúria.' },
      }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      klass.reload
      expect(klass.short_description).to eq('Guerreiro berserker movido pela fúria.')
    end
  end

  describe 'DELETE /api/v1/admin/klasses/:id' do
    let!(:klass) { create(:klass, name: 'Removivel') }

    it 'remove classe' do
      expect {
        delete "/api/v1/admin/klasses/#{klass.id}", headers: headers
      }.to change(Klass, :count).by(-1)
      expect(response).to have_http_status(:ok)
    end
  end
end
