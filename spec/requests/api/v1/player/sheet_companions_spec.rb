# frozen_string_literal: true

require 'rails_helper'

# `addCompanion` no front só fazia `setCharacters` — nenhuma chamada de API.
# Medido antes: 0 fichas tinham companion salvo. Tudo que o jogador adicionava
# (familiar, montaria, companheiro animal) sumia no reload.
RSpec.describe 'Api::V1::Player::SheetCompanionsController', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:character) { create(:character, user: user, name: 'Companion Spec PC') }
  let!(:sheet) { create(:sheet, character: character) }

  def corcel(id: 'cmp-1', name: 'Cavalo de Guerra')
    { id: id, name: name, type: 'mount', ownerId: 'pc-1', hpMax: 19, hpCurrent: 19, ac: 11 }
  end

  def post_companion(payload)
    post "/api/v1/player/sheets/#{sheet.id}/companions",
         params: { companion: payload }, headers: headers, as: :json
  end

  it 'PERSISTE o companion — é o buraco que este endpoint fecha' do
    post_companion(corcel)

    expect(response).to have_http_status(:created)
    expect(sheet.reload.companions.size).to eq(1)
    expect(sheet.companions.first['name']).to eq('Cavalo de Guerra')
    # o objeto rico do template sobrevive inteiro
    expect(sheet.companions.first['hpMax']).to eq(19)
  end

  it 'lista o que foi salvo' do
    post_companion(corcel)
    post_companion(corcel(id: 'cmp-2', name: 'Coruja'))

    get "/api/v1/player/sheets/#{sheet.id}/companions", headers: headers, as: :json

    expect(response.parsed_body['companions'].map { |c| c['name'] }).to match_array(['Cavalo de Guerra', 'Coruja'])
  end

  it 'REGRESSAO: o mesmo id nao vira dois cards' do
    post_companion(corcel)
    post_companion(corcel(name: 'Cavalo de Guerra (renomeado)'))

    expect(sheet.reload.companions.size).to eq(1)
    expect(sheet.companions.first['name']).to eq('Cavalo de Guerra (renomeado)')
  end

  it 'atualiza sem trocar o id (a chave do remove)' do
    post_companion(corcel)

    patch "/api/v1/player/sheets/#{sheet.id}/companions/cmp-1",
          params: { companion: { hpCurrent: 7, id: 'OUTRO' } }, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    c = sheet.reload.companions.first
    expect(c['hpCurrent']).to eq(7)
    expect(c['id']).to eq('cmp-1')
  end

  it 'remove' do
    post_companion(corcel)

    delete "/api/v1/player/sheets/#{sheet.id}/companions/cmp-1", headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(sheet.reload.companions).to eq([])
  end

  it 'recusa payload sem id ou sem nome — sem chave nao ha operacao granular' do
    post_companion({ name: 'Sem id' })
    expect(response).to have_http_status(:unprocessable_entity)

    post_companion({ id: 'x' })
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'atualizar companion inexistente devolve 404' do
    patch "/api/v1/player/sheets/#{sheet.id}/companions/nao-existe",
          params: { companion: { hpCurrent: 1 } }, headers: headers, as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'a ficha de OUTRO jogador nao aceita companion' do
    outro = create(:character, user: create(:user), name: 'Alheio')
    alheia = create(:sheet, character: outro)

    post "/api/v1/player/sheets/#{alheia.id}/companions",
         params: { companion: corcel }, headers: headers, as: :json

    expect(response).to have_http_status(:not_found)
    expect(alheia.reload.companions).to eq([])
  end

  it 'adicionar um NAO apaga o outro (o blob inteiro nao e reescrito as cegas)' do
    post_companion(corcel)
    post_companion(corcel(id: 'cmp-2', name: 'Coruja'))

    expect(sheet.reload.companions.map { |c| c['id'] }).to match_array(%w[cmp-1 cmp-2])
  end
end
