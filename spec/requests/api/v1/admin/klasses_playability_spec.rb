# frozen_string_literal: true

require 'rails_helper'

# Espelha `admin/races_playability_spec.rb` para Classes/Subclasses.
RSpec.describe 'Api::V1::Admin::Klasses playability', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:dm_user) { create(:user, role: dm_role) }
  let(:player) { create(:user, role: player_role) }

  it 'allows a site-wide DM to toggle a klass and sub-klass playability' do
    klass = create(:klass, playable: true)
    sub_klass = create(:sub_klass, klass: klass, playable: true)

    patch "/api/v1/admin/klasses/#{klass.id}",
          params: { klass: { playable: false } },
          headers: bearer_headers_for(dm_user),
          as: :json

    expect(response).to have_http_status(:ok), -> { response.body }
    expect(klass.reload.playable).to eq(false)
    expect(response.parsed_body.dig('klass', 'playable')).to eq(false)

    patch "/api/v1/admin/sub_klasses/#{sub_klass.id}",
          params: { sub_klass: { playable: false } },
          headers: bearer_headers_for(dm_user),
          as: :json

    expect(response).to have_http_status(:ok), -> { response.body }
    expect(sub_klass.reload.playable).to eq(false)
    expect(response.parsed_body.dig('sub_klass', 'playable')).to eq(false)
  end

  it 'rejects plain players' do
    klass = create(:klass)

    patch "/api/v1/admin/klasses/#{klass.id}",
          params: { klass: { playable: false } },
          headers: bearer_headers_for(player),
          as: :json

    expect(response).to have_http_status(:forbidden)
  end

  it 'allows a DM to persist a terrain_spells override on a sub-klass' do
    klass = create(:klass)
    sub_klass = create(:sub_klass, klass: klass, name: 'Círculo da Terra')

    override = [
      {
        terrain: 'Vulcânico',
        spells: [
          { level: 3, spellLevel: 2, spells: ['Esfera Flamejante', 'Aquecer Metal'] },
          { level: 5, spellLevel: 3, spells: ['Bola de Fogo'] },
        ],
      },
    ]

    patch "/api/v1/admin/sub_klasses/#{sub_klass.id}",
          params: { sub_klass: { terrain_spells: override } },
          headers: bearer_headers_for(dm_user),
          as: :json

    expect(response).to have_http_status(:ok), -> { response.body }
    persisted = sub_klass.reload.terrain_spells
    expect(persisted).to be_present
    expect(persisted.first['terrain']).to eq('Vulcânico')
    expect(persisted.first['spells'].first['spells']).to eq(['Esfera Flamejante', 'Aquecer Metal'])
  end
end
