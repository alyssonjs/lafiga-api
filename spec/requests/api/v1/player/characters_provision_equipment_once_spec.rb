# frozen_string_literal: true

require 'rails_helper'

# O equipamento inicial entra UMA vez: na PRIMEIRA provisão.
#
# Antes, cada "Concluir Edição" no wizard apagava o lote provisionado e
# reinseria-o. Duas consequências, ambas silenciosas:
#
#   1. o que o jogador tinha TIRADO da bolsa voltava — a mochila enchia-se de
#      novo com as tochas e as rações que ele já tinha largado;
#   2. as moedas do antecedente eram somadas outra vez, porque
#      `apply_coin_delta!` SOMA em vez de definir — a algibeira de 25 po do
#      nobre engordava a cada atualização.
#
# Mudar equipamento depois é pelos endpoints `/sheet_items` (o CRUD do
# inventário ao vivo), que nunca carregam `provisioning_run_id`.
RSpec.describe 'provision — equipamento inicial só na primeira vez', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }

  def payload_com_equipamento
    p = minimal_l1_barbarian_provision_payload(
      race: human_race,
      sub_race: human_standard_subrace(human_race),
      klass: barbarian_klass,
      background: acolyte_background,
      alignment: lawful_good_alignment
    )
    p[:wizard][:equipment] = {
      equipmentPicks: [
        { item_index: 'greataxe', item_name: 'Machado Grande', category: 'class',
          quantity: 1, equipped: false, source: 'class' },
        { item_index: 'azagaia', item_name: 'Azagaia', category: 'class',
          quantity: 4, equipped: false, source: 'class' }
      ]
    }
    p
  end

  def provisionar(payload)
    post '/api/v1/player/characters/provision', params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:created), -> { response.body }
    Character.find(response.parsed_body.dig('character', 'id')).sheet.reload
  end

  it 'a PRIMEIRA provisao coloca o equipamento na bolsa' do
    sheet = provisionar(payload_com_equipamento)

    nomes = sheet.sheet_items.where(source: 'class').pluck(:item_name)
    expect(nomes).to include('Machado Grande', 'Azagaia')
  end

  it 'REGRESSAO: atualizar NAO repoe o que o jogador tirou da bolsa' do
    payload = payload_com_equipamento
    sheet = provisionar(payload)
    machado = sheet.sheet_items.find_by(item_name: 'Machado Grande')
    machado.destroy!

    # Mesma ficha, "Concluir Edição" outra vez.
    payload[:character][:id] = sheet.character_id
    provisionar(payload)

    expect(sheet.sheet_items.reload.where(item_name: 'Machado Grande')).to be_empty
  end

  it 'REGRESSAO: atualizar NAO soma as moedas do antecedente outra vez' do
    payload = payload_com_equipamento
    sheet = provisionar(payload)
    antes = sheet.coins.dup

    payload[:character][:id] = sheet.character_id
    provisionar(payload)

    expect(sheet.reload.coins).to eq(antes)
  end

  it 'atualizar NAO duplica o que continua la' do
    payload = payload_com_equipamento
    sheet = provisionar(payload)
    antes = sheet.sheet_items.where(source: 'class').count

    payload[:character][:id] = sheet.character_id
    provisionar(payload)

    expect(sheet.sheet_items.reload.where(source: 'class').count).to eq(antes)
  end

  it 'itens MANUAIS continuam intocados — nunca foram do provisionamento' do
    payload = payload_com_equipamento
    sheet = provisionar(payload)
    manual = SheetItem.create!(sheet: sheet, item_name: 'Corda comprada', category: 'Itens Gerais',
                               quantity: 1, source: 'manual')

    payload[:character][:id] = sheet.character_id
    provisionar(payload)

    expect(manual.reload).to be_persisted
    expect(sheet.sheet_items.reload.where(item_name: 'Corda comprada').count).to eq(1)
  end

  it 'a ficha fica MARCADA, para nao depender so do lote' do
    sheet = provisionar(payload_com_equipamento)

    marca = (sheet.reload.metadata || {})['starting_equipment']
    expect(marca).to include('class', 'background')
  end
end
