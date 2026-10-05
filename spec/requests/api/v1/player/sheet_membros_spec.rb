# frozen_string_literal: true

require 'rails_helper'

# O VISUAL do membro substituído (05/10): o dono troca o material e a cor; o tipo, os efeitos e a arma são do Mestre.
RSpec.describe 'Api::V1::Player::SheetMembros', type: :request do
  let(:dono) { create(:user) }
  let(:outro) { create(:user) }
  let(:character) { create(:character, user: dono) }
  let!(:sheet) do
    create(:sheet, character: character, avatar_customization: { 'gender' => 'feminine', 'membros' => {
      'braco_esquerdo' => { 'estado' => 'substituido', 'substituto' => {
        'tipo' => 'protese', 'material' => 'metal', 'cor' => 'steel', 'efeitos' => [{ 'kind' => 'ac_bonus', 'value' => 1 }],
      } },
      'olho_direito' => { 'estado' => 'perdido' },
    } })
  end
  let(:corpo) { JSON.parse(response.body) }

  def pinta(payload, quem: dono)
    patch "/api/v1/player/sheets/#{sheet.id}/membros", params: { membros: payload }.to_json,
                                                       headers: bearer_headers_for(quem).merge('Content-Type' => 'application/json')
  end

  it 'o dono troca o material e a cor; os efeitos ficam', :aggregate_failures do
    pinta({ braco_esquerdo: { material: 'madeira', cor: 'walnut', efeitos: [] } })

    expect(response).to have_http_status(:ok)
    sub = sheet.reload.avatar_customization.dig('membros', 'braco_esquerdo', 'substituto')
    expect(sub).to include('tipo' => 'protese', 'material' => 'madeira', 'cor' => 'walnut')
    expect(sub['efeitos']).to eq([{ 'kind' => 'ac_bonus', 'value' => 1 }])
    expect(sheet.avatar_customization['gender']).to eq('feminine')
  end

  it '⚠️ o jogador não mexe em membro que não está substituído (nem o devolve)', :aggregate_failures do
    pinta({ olho_direito: { cor: 'gold' } })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(sheet.reload.avatar_customization.dig('membros', 'olho_direito')).to eq('estado' => 'perdido')
  end

  it 'outro jogador não mexe' do
    pinta({ braco_esquerdo: { cor: 'gold' } }, quem: outro)
    expect(response).to have_http_status(:not_found)
  end
end
