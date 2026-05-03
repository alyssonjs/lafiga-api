# frozen_string_literal: true

require 'rails_helper'

# Regressao para o fluxo "Editar Classe > seção Subclasses" do front-lafiga.
# O `ClassFormModal.tsx` coleta `name + description` (RichTextEditor) por
# subclasse; o `ClassContext.updateClass` agora sincroniza cada uma via
# `PATCH /api/v1/admin/sub_klasses/:id`. Antes desta integracao o controller
# ja permitia `description`, mas faltava cobertura.
RSpec.describe 'Api::V1::Admin::SubKlasses', type: :request do
  let(:admin_role)  { Role.find_by(name: 'Admin')  || create(:role, name: 'Admin') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:admin)       { create(:user, role: admin_role) }
  let(:player)      { create(:user, role: player_role) }
  let(:headers)     { bearer_headers_for(admin).merge('Content-Type' => 'application/json') }
  let!(:klass)      { create(:klass, name: 'Bárbaro', api_index: "barbarian_#{SecureRandom.hex(4)}", hit_die: 12) }

  describe 'PATCH /api/v1/admin/sub_klasses/:id' do
    let!(:sub_klass) do
      create(:sub_klass,
             klass: klass,
             name: 'Senda do Berserker',
             api_index: "senda_berserker_#{SecureRandom.hex(4)}",
             description: 'Descricao antiga.')
    end

    it 'persiste novo description editado pelo modal' do
      patch "/api/v1/admin/sub_klasses/#{sub_klass.id}", params: {
        sub_klass: {
          name: 'Senda do Berserker',
          description: '<p>Versão homebrew com fúria estendida.</p>',
        },
      }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to have_key('sub_klass')
      expect(body['sub_klass']['description']).to include('homebrew')

      sub_klass.reload
      expect(sub_klass.description).to include('homebrew com fúria')
    end

    it 'aceita api_index alem de id numerico (set_sub_klass)' do
      patch "/api/v1/admin/sub_klasses/#{sub_klass.api_index}", params: {
        sub_klass: { description: '<p>via api_index</p>' },
      }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      sub_klass.reload
      expect(sub_klass.description).to include('via api_index')
    end

    it 'rejeita Player com 401/403' do
      patch "/api/v1/admin/sub_klasses/#{sub_klass.id}", params: {
        sub_klass: { description: 'tentativa indevida' },
      }.to_json, headers: bearer_headers_for(player).merge('Content-Type' => 'application/json')

      expect(response.status).to be_in([401, 403])
    end
  end

  describe 'POST /api/v1/admin/sub_klasses' do
    it 'cria subclasse com description' do
      payload = {
        sub_klass: {
          klass_id: klass.id,
          name: 'Senda Custom',
          api_index: "senda_custom_#{SecureRandom.hex(4)}",
          description: '<p>Subclasse homebrew nova.</p>',
        },
      }
      expect {
        post '/api/v1/admin/sub_klasses', params: payload.to_json, headers: headers
      }.to change(SubKlass, :count).by(1)
      expect(response).to have_http_status(:created)
    end
  end
end
