# frozen_string_literal: true

require 'rails_helper'

# GET /battle_maps/:id/background — serve o fundo para <img> (sem header de auth;
# a autorização é o `sig` assinado). O caso do arquivo AUSENTE importa: o
# registro do anexo pode existir sem o arquivo no storage (banco restaurado sem
# `storage/`, volume perdido) e isso não pode virar 500.
RSpec.describe 'Api::V1::Player::BattleMaps#background', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:dm)      { create(:user, role: dm_role) }
  let(:map)     { create(:battle_map, user: dm) }

  def attach_background!(data: 'conteudo-fake-png')
    map.background_image.attach(
      io: StringIO.new(data), filename: 'fundo.png', content_type: 'image/png',
    )
    map.reload
  end

  def sig_for(blob)
    Rails.application.message_verifier('battle_map_background').generate(blob.id)
  end

  def get_background(sig:)
    get "/api/v1/player/battle_maps/#{map.id}/background", params: { sig: sig }
  end

  it 'serve o arquivo quando ele existe' do
    attach_background!
    get_background(sig: sig_for(map.background_image.blob))

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq('conteudo-fake-png')
  end

  it 'REGRESSAO: arquivo sumido do storage responde 404, nao 500' do
    attach_background!
    blob = map.background_image.blob
    # Simula o registro sem arquivo: apaga so o arquivo, mantendo o anexo.
    blob.service.delete(blob.key)

    get_background(sig: sig_for(blob))

    expect(response).to have_http_status(:not_found)
  end

  it '404 quando o mapa nao tem fundo anexado' do
    get_background(sig: 'qualquer')

    expect(response).to have_http_status(:not_found)
  end

  it '403 com assinatura invalida (o id do mapa sozinho nao basta)' do
    attach_background!
    get_background(sig: 'assinatura-forjada')

    expect(response).to have_http_status(:forbidden)
  end
end
