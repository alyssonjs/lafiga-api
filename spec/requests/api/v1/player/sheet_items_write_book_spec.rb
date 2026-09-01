# frozen_string_literal: true

require 'rails_helper'

# Escrever no livro/tomo. Endpoint PRÓPRIO porque ele MESCLA o `props_json` —
# o `update` genérico recebe o hash inteiro e apagaria sintonia, o vínculo da
# munição com a aljava e o peso da linha.
RSpec.describe 'Api::V1::Player::SheetItemsController write_book', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:race) { human_race }
  let(:sub_race) { human_standard_subrace(race) }
  let(:character) { create(:character, user: user, name: 'Livro Spec PC') }
  let!(:sheet) { create(:sheet, character: character, race: race, sub_race: sub_race) }

  let(:livro) do
    SheetItem.create!(
      sheet: sheet, item_name: 'Tomo de capa de couro', item_index: 'tomo-couro',
      category: 'Itens Gerais', quantity: 1, equipped: false, source: 'test',
      props_json: { 'weight_lb' => 3, 'attuned' => true }
    )
  end

  it 'grava o conteúdo e devolve em `props`' do
    post "/api/v1/player/sheet_items/#{livro.id}/write_book",
         params: { content: '<p>As notas de Yula</p>' }, headers: headers, as: :json

    expect(response).to have_http_status(:ok), -> { response.body }
    expect(response.parsed_body['sheet_item']['props']['book_content']).to eq('<p>As notas de Yula</p>')
    expect(livro.reload.props_json['book_content']).to eq('<p>As notas de Yula</p>')
  end

  it '⚠️ MESCLA: sintonia e peso sobrevivem à escrita' do
    post "/api/v1/player/sheet_items/#{livro.id}/write_book",
         params: { content: 'texto' }, headers: headers, as: :json

    livro.reload
    expect(livro.props_json['attuned']).to eq(true)
    expect(livro.props_json['weight_lb']).to eq(3)
  end

  it 'reescrever substitui só o conteúdo' do
    post "/api/v1/player/sheet_items/#{livro.id}/write_book",
         params: { content: 'primeira versão' }, headers: headers, as: :json
    post "/api/v1/player/sheet_items/#{livro.id}/write_book",
         params: { content: 'segunda versão' }, headers: headers, as: :json

    livro.reload
    expect(livro.props_json['book_content']).to eq('segunda versão')
    expect(livro.props_json['attuned']).to eq(true)
  end

  it 'apagar tudo deixa o livro em branco (não remove a chave nem as outras props)' do
    post "/api/v1/player/sheet_items/#{livro.id}/write_book",
         params: { content: 'algo' }, headers: headers, as: :json
    post "/api/v1/player/sheet_items/#{livro.id}/write_book",
         params: { content: '' }, headers: headers, as: :json

    expect(livro.reload.props_json['book_content']).to eq('')
    expect(livro.props_json['weight_lb']).to eq(3)
  end

  it 'ficha de OUTRO jogador não pode escrever' do
    outro = create(:user)
    post "/api/v1/player/sheet_items/#{livro.id}/write_book",
         params: { content: 'invasao' }, headers: bearer_headers_for(outro), as: :json

    expect(response).to have_http_status(:forbidden).or have_http_status(:not_found)
    expect(livro.reload.props_json['book_content']).to be_nil
  end
end
