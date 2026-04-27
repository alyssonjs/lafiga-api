# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Public::GroupsController', type: :request do
  let(:group) { create(:group, name: 'Grupo Visível') }
  let(:user) { create(:user) }
  let(:klass) { create(:klass, name: 'Mago', api_index: "wizard_pub_#{SecureRandom.hex(4)}") }
  let(:character) { create(:character, user: user, name: 'PC Público', group: group) }
  let(:sheet) { create(:sheet, character: character) }
  let!(:_sk) { create(:sheet_klass, sheet: sheet, klass: klass, level: 2) }

  it 'GET /api/v1/public/groups/:id devolve group serializado (members, não exige membro autenticado)' do
    get "/api/v1/public/groups/#{group.id}"

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    g = body['group']
    expect(g['name']).to eq('Grupo Visível')
    expect(g['members'].length).to eq(1)
    m = g['members'][0]
    expect(m['id']).to eq(character.id)
    expect(m['class_name']).to include('Mago')
  end
end
