# frozen_string_literal: true

require 'rails_helper'

# GET /battle_maps/:id/land_mask — serve a silhueta de terra importada (alfa =
# terra) para <img>, SEM header de auth: a autorização é o `sig` assinado, o
# mesmo esquema do #background. É a semente da Ferramenta de Terra; sem o
# skip_before_action correto o <img> tomava 401 e o litoral não aparecia.
RSpec.describe 'Api::V1::Player::BattleMaps#land_mask', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:dm)      { create(:user, role: dm_role) }
  let(:map)     { create(:battle_map, user: dm) }

  def attach_mask!(data: 'conteudo-fake-webp')
    map.land_mask.attach(
      io: StringIO.new(data), filename: 'mask.webp', content_type: 'image/webp',
    )
    map.reload
  end

  def sig_for(blob)
    Rails.application.message_verifier('battle_map_background').generate(blob.id)
  end

  def get_mask(sig:)
    get "/api/v1/player/battle_maps/#{map.id}/land_mask", params: { sig: sig }
  end

  it 'serve a silhueta SEM header de auth (a autz é o sig)' do
    attach_mask!
    get_mask(sig: sig_for(map.land_mask.blob))

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq('conteudo-fake-webp')
  end

  it 'REGRESSAO: arquivo sumido do storage responde 404, nao 500' do
    attach_mask!
    blob = map.land_mask.blob
    blob.service.delete(blob.key)

    get_mask(sig: sig_for(blob))

    expect(response).to have_http_status(:not_found)
  end

  it '404 quando o mapa nao tem silhueta anexada' do
    get_mask(sig: 'qualquer')

    expect(response).to have_http_status(:not_found)
  end

  it '403 com assinatura invalida' do
    attach_mask!
    get_mask(sig: 'assinatura-forjada')

    expect(response).to have_http_status(:forbidden)
  end
end
