# frozen_string_literal: true

require 'rails_helper'

# MEMBRO PERDIDO (04/10, a mesa: "isso só o mestre vai ter acesso"). O Mestre marca, a aparência do personagem leva —
# e o desenho do LPC some com o membro (no mapa, pela foto do token). Ver `Sheets::Membros`.
RSpec.describe 'Api::V1::Admin::SheetMembros', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dm_role) { Role.find_or_create_by!(name: 'DM') }
  let(:dm) { create(:user, role: dm_role) }
  let(:headers) { bearer_headers_for(dm).merge('Content-Type' => 'application/json') }
  let(:dono) { create(:user) }
  let(:character) { create(:character, user: dono) }
  let!(:sheet) { create(:sheet, character: character, avatar_customization: { 'gender' => 'masculine', 'lpc' => { 'v' => 1, 'pele' => 'olive' } }) }
  let(:corpo) { JSON.parse(response.body) }

  def marca(payload, como: headers)
    patch "/api/v1/admin/sheets/#{sheet.id}/membros", params: { membros: payload }.to_json, headers: como
  end

  it 'o Mestre marca o membro perdido: grava na aparência, com quem e quando', :aggregate_failures do
    marca({ mao_direito: { estado: 'perdido' } })

    expect(response).to have_http_status(:ok)
    expect(corpo.dig('membros', 'mao_direito', 'estado')).to eq('perdido')
    linha = sheet.reload.avatar_customization.dig('membros', 'mao_direito')
    expect(linha['by_user_id']).to eq(dm.id)
    expect(linha['at']).to be_present
  end

  it 'não mexe no resto da aparência (o LPC, o gênero)' do
    marca({ olho_esquerdo: { estado: 'perdido' } })
    expect(sheet.reload.avatar_customization).to include('gender' => 'masculine', 'lpc' => { 'v' => 1, 'pele' => 'olive' })
  end

  it 'patch PARCIAL; `null` devolve o membro; sem nenhum, a chave sai', :aggregate_failures do
    marca({ mao_direito: { estado: 'perdido' } })
    marca({ perna_esquerdo: { estado: 'perdido' } })
    expect(sheet.reload.avatar_customization['membros'].keys).to contain_exactly('mao_direito', 'perna_esquerdo')

    marca({ mao_direito: nil, perna_esquerdo: nil })
    expect(sheet.reload.avatar_customization).not_to have_key('membros')
  end

  it '⚠️ a data em que o membro se foi não muda ao reenviar o mesmo estado' do
    marca({ canela_direito: { estado: 'perdido' } })
    antes = sheet.reload.avatar_customization.dig('membros', 'canela_direito', 'at')
    travel_to(2.days.from_now) { marca({ canela_direito: { estado: 'perdido' } }) }
    expect(sheet.reload.avatar_customization.dig('membros', 'canela_direito', 'at')).to eq(antes)
  end

  it 'recusa membro e estado fora da lista', :aggregate_failures do
    marca({ cauda_direito: { estado: 'perdido' } })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(corpo['errors'].join).to include('cauda_direito')

    marca({ mao_direito: { estado: 'gancho' } })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(sheet.reload.avatar_customization).not_to have_key('membros')
  end

  it '⚠️ o JOGADOR não marca (nem na própria ficha)' do
    marca({ mao_direito: { estado: 'perdido' } }, como: bearer_headers_for(dono).merge('Content-Type' => 'application/json'))
    expect(response).to have_http_status(:forbidden)
    expect(sheet.reload.avatar_customization).not_to have_key('membros')
  end

  it 'o token do personagem nos mapas recebe a aparência nova (a mesa vê na hora)' do
    mapa = create(:battle_map, user: dm, tokens: [{ 'id' => 't1', 'characterId' => character.id.to_s, 'name' => 'X', 'x' => 1, 'y' => 1, 'size' => 1,
                                                     'chibiCustomization' => { 'gender' => 'masculine' } }])
    marca({ braco_esquerdo: { estado: 'perdido' } })
    expect(mapa.reload.tokens.first.dig('chibiCustomization', 'membros', 'braco_esquerdo', 'estado')).to eq('perdido')
  end
end
