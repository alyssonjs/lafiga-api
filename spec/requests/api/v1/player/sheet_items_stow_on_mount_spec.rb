# frozen_string_literal: true

require 'rails_helper'

# A montaria carrega carga (PHB: 420 lb numa mula, 1320 num elefante), mas nao
# havia onde POR o item. Este endpoint espelha a alocacao de municao na aljava —
# o vinculo vive em `props_json`, com lock da ficha.
RSpec.describe 'Api::V1::Player::SheetItemsController stow_on_mount', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:character) { create(:character, user: user, name: 'Stow Spec PC') }
  let!(:sheet) do
    s = create(:sheet, character: character)
    s.update!(companions: [
                { 'id' => 'mnt-1', 'name' => 'Mula', 'type' => 'mount', 'hpMax' => 11, 'hpCurrent' => 11 },
                { 'id' => 'fam-1', 'name' => 'Coruja', 'type' => 'familiar', 'hpMax' => 1, 'hpCurrent' => 1 },
              ])
    s
  end

  def bag!(nome: 'Corda', qtd: 1)
    SheetItem.create!(sheet: sheet, item_name: nome, item_index: nome.parameterize,
                      category: 'Equipamento', quantity: qtd, source: 'test')
  end

  def stow(item, companion_id:, quantity: 1)
    post "/api/v1/player/sheet_items/#{item.id}/stow_on_mount",
         params: { companion_id: companion_id, quantity: quantity }, headers: headers, as: :json
  end

  def prop(si) = (si.reload.props_json || {})[SheetItem::MOUNT_CONTAINER_PROP]

  it 'guarda o item na montaria' do
    item = bag!

    stow(item, companion_id: 'mnt-1')

    expect(response).to have_http_status(:ok)
    expect(prop(item)).to eq('mnt-1')
  end

  it 'companion_id nulo TIRA da montaria (volta para a bolsa)' do
    item = bag!
    stow(item, companion_id: 'mnt-1')

    stow(item, companion_id: nil)

    expect(response).to have_http_status(:ok)
    expect(prop(item)).to be_nil
  end

  it 'REGRESSAO: familiar nao carrega carga — so montaria' do
    item = bag!

    stow(item, companion_id: 'fam-1')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to match(/nao e uma montaria|não é uma montaria/i)
    expect(prop(item)).to be_nil
  end

  it 'companion inexistente e recusado' do
    stow(bag!, companion_id: 'nao-existe')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to match(/nao encontrada|não encontrada/i)
  end

  it 'guarda PARTE de uma pilha, deixando o resto na bolsa' do
    item = bag!(nome: 'Rações', qtd: 10)

    stow(item, companion_id: 'mnt-1', quantity: 4)

    expect(response).to have_http_status(:ok)
    linhas = sheet.sheet_items.where(item_name: 'Rações')
    na_montaria = linhas.select { |l| (l.props_json || {})[SheetItem::MOUNT_CONTAINER_PROP] == 'mnt-1' }
    na_bolsa    = linhas.reject { |l| (l.props_json || {})[SheetItem::MOUNT_CONTAINER_PROP] }
    expect(na_montaria.sum(&:quantity)).to eq(4)
    expect(na_bolsa.sum(&:quantity)).to eq(6)
  end

  it 'quantidade maior que a pilha e recusada' do
    stow(bag!(qtd: 2), companion_id: 'mnt-1', quantity: 5)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to match(/quantidade inválida/i)
  end

  it 'REGRESSAO: dispensar a montaria DEVOLVE a carga, nao a evapora' do
    item = bag!
    stow(item, companion_id: 'mnt-1')

    delete "/api/v1/player/sheets/#{sheet.id}/companions/mnt-1", headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(SheetItem.find_by(id: item.id)).to be_present
    expect(prop(item)).to be_nil
  end
end
