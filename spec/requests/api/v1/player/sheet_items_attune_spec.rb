# frozen_string_literal: true

require 'rails_helper'

# A UI de sintonia existia so no cliente: `CharacterBag` gravava por
# `persistItems`, que faz early-return no modo controlado, entao na ficha vinda
# da API a chave NUNCA chegava ao banco (0 de 1041 sheet_items a tinham). Com o
# teto so no front, `countAttunedItems` sempre dava 0 e o limite de 3 nunca
# mordia. Estes exemplos travam a regra no servidor.
RSpec.describe 'Api::V1::Player::SheetItemsController attune', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:race) { human_race }
  let(:sub_race) { human_standard_subrace(race) }
  let(:character) { create(:character, user: user, name: 'Attune Spec PC') }
  let!(:sheet) { create(:sheet, character: character, race: race, sub_race: sub_race) }

  def magic_item!(nome)
    slug = "spec-att-#{SecureRandom.hex(4)}"
    MagicItem.create!(name: nome, slug: slug, rarity: 'rare', category: 'ring',
                      requires_attunement: true)
    slug
  end

  def bag_item!(nome, slug)
    SheetItem.create!(sheet: sheet, item_name: nome, item_index: slug,
                      category: 'Vestuário', quantity: 1, source: 'test')
  end

  def attune(item)
    post "/api/v1/player/sheet_items/#{item.id}/attune", headers: headers, as: :json
  end

  it 'sintoniza e PERSISTE em props_json' do
    item = bag_item!('Anel de Proteção', magic_item!('Anel de Proteção'))

    attune(item)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('sheet_item', 'props', 'attuned')).to be true
    expect(item.reload.props_json['attuned']).to be true
  end

  it 'REGRESSAO: o teto de 3 morde no SERVIDOR' do
    3.times { |i| attune(bag_item!("Item #{i}", magic_item!("Item #{i}"))) }
    quarto = bag_item!('Quarto', magic_item!('Quarto'))

    attune(quarto)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to match(/limite de 3/i)
    expect(Sheets::Attunement.attuned?(quarto.reload)).to be false
  end

  it 'item que nao exige sintonia e recusado' do
    item = SheetItem.create!(sheet: sheet, item_name: 'Corda', item_index: 'corda',
                             category: 'Equipamento', quantity: 1, source: 'test')

    attune(item)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to match(/não exige sintonia/i)
  end

  it 'quebrar a sintonia e sempre permitido — e libera a vaga' do
    itens = 3.times.map { |i| bag_item!("Item #{i}", magic_item!("Item #{i}")) }
    itens.each { |it| attune(it) }
    quarto = bag_item!('Quarto', magic_item!('Quarto'))
    attune(quarto)
    expect(response).to have_http_status(:unprocessable_entity)

    post "/api/v1/player/sheet_items/#{itens.first.id}/unattune", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(itens.first.reload.props_json['attuned']).to be false

    attune(quarto)
    expect(response).to have_http_status(:ok)
  end

  it 'sintonizar duas vezes e idempotente, nao consome duas vagas' do
    item = bag_item!('Anel', magic_item!('Anel'))
    2.times { attune(item) }

    expect(response).to have_http_status(:ok)
    expect(Sheets::Attunement.attuned_count(sheet.reload)).to eq(1)
  end

  it 'a ficha de OUTRO jogador nao pode ser sintonizada' do
    outro = create(:user)
    outro_char = create(:character, user: outro, name: 'Alheio')
    outra_sheet = create(:sheet, character: outro_char, race: race, sub_race: sub_race)
    alheio = SheetItem.create!(sheet: outra_sheet, item_name: 'Anel', item_index: magic_item!('Anel'),
                               category: 'Vestuário', quantity: 1, source: 'test')

    attune(alheio)

    expect(response.status).to be_in([401, 403, 404])
    expect(Sheets::Attunement.attuned?(alheio.reload)).to be false
  end
end
