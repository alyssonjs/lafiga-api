# frozen_string_literal: true

require 'rails_helper'

# Instrumento musical eh FERRAMENTA no PHB. A aba propria filtra por
# `category: instrument` em QUALQUER kind, para absorver o que ja existe como
# `gear` sem migration — e os baldes de origem excluem a categoria para o mesmo
# item nao aparecer em duas abas.
RSpec.describe 'Api::V1::Public::EquipmentController instrumentos', type: :request do
  let!(:tool_instrument) do
    Item.create!(name: 'Spec Alaude', api_index: "spec-alaude-#{SecureRandom.hex(3)}",
                 kind: 'tool', category: 'instrument')
  end
  let!(:legacy_gear_instrument) do
    Item.create!(name: 'Spec Lira Legada', api_index: "spec-lira-#{SecureRandom.hex(3)}",
                 kind: 'gear', category: 'instrument')
  end
  let!(:plain_tool) do
    Item.create!(name: 'Spec Ferramenta de Ladrao', api_index: "spec-tool-#{SecureRandom.hex(3)}",
                 kind: 'tool', category: 'thieves-tools')
  end
  let!(:tool_sem_categoria) do
    Item.create!(name: 'Spec Ferramenta Sem Categoria', api_index: "spec-toolnil-#{SecureRandom.hex(3)}",
                 kind: 'tool', category: nil)
  end
  # `category` preenchida de proposito: `gear` com categoria NULA nao aparece na
  # aba por um bug PRE-EXISTENTE (`where.not` NULL-unsafe no `pack`), alheio a
  # instrumentos e deliberadamente nao alterado aqui.
  let!(:plain_gear) do
    Item.create!(name: 'Spec Corda', api_index: "spec-gear-#{SecureRandom.hex(3)}",
                 kind: 'gear', category: 'gear')
  end

  def indexes_for(category)
    get "/api/v1/public/equipment_list/#{category}"
    expect(response).to have_http_status(:ok)
    Array(response.parsed_body['equipment']).map { |e| e['index'] }
  end

  it 'a aba junta instrumento de `tool` E o legado de `gear`' do
    idx = indexes_for('instruments')

    expect(idx).to include(tool_instrument.api_index, legacy_gear_instrument.api_index)
  end

  it 'REGRESSAO: instrumento nao aparece tambem em Ferramentas' do
    idx = indexes_for('tools')

    expect(idx).to include(plain_tool.api_index)
    expect(idx).not_to include(tool_instrument.api_index)
  end

  it 'REGRESSAO: excluir instrumento nao pode derrubar ferramenta com categoria NULA' do
    # `where.not` gera NOT IN (NULL-unsafe) e levaria 18 das 20 ferramentas
    # junto. Por isso o balde usa `IS DISTINCT FROM`.
    expect(indexes_for('tools')).to include(tool_sem_categoria.api_index)
  end

  it 'REGRESSAO: instrumento legado nao aparece tambem em Equipamento' do
    idx = indexes_for('gear')

    expect(idx).to include(plain_gear.api_index)
    expect(idx).not_to include(legacy_gear_instrument.api_index)
  end

  it 'aceita o alias em portugues' do
    expect(indexes_for('instrumentos')).to include(tool_instrument.api_index)
  end

  it 'REGRESSAO: instrumento continua no snapshot da bolsa' do
    # os baldes :gear/:tools passaram a excluir a categoria — sem `instruments`
    # no snapshot, o item sumiria do modal "Adicionar item".
    get '/api/v1/public/equipment_catalog_snapshot'

    expect(response).to have_http_status(:ok)
    idx = Array(response.parsed_body.dig('by_category', 'instruments')).map { |e| e['index'] }
    expect(idx).to include(tool_instrument.api_index, legacy_gear_instrument.api_index)
  end

  it 'o rotulo da categoria diz "instruments" nos dois kinds' do
    # sem isto o modal da bolsa mostraria "Adventuring Gear" para um alaude.
    get "/api/v1/public/equipment_list/instruments"
    rows = Array(response.parsed_body['equipment'])

    idx = rows.map { |e| e.dig('equipment_category', 'index') }.uniq
    expect(idx).to eq(['instruments'])
  end

  it 'devolve o `card_icon_id` que o mestre escolheu' do
    # sem isto o icone e gravado em props e a listagem nunca o ve.
    tool_instrument.update!(props: { 'card_icon_id' => 'lute', 'chibi_weapon_svg_id' => 'lyre' })

    get '/api/v1/public/equipment_list/instruments'
    row = Array(response.parsed_body['equipment']).find { |e| e['index'] == tool_instrument.api_index }

    expect(row['card_icon_id']).to eq('lute')
    # o MODELO tambem: e ele que o card desenha quando existe
    expect(row['chibi_weapon_svg_id']).to eq('lyre')
  end

  it 'instrumento sem icone nao devolve a chave (o front cai no fallback)' do
    get '/api/v1/public/equipment_list/instruments'
    row = Array(response.parsed_body['equipment']).find { |e| e['index'] == legacy_gear_instrument.api_index }

    expect(row).not_to have_key('card_icon_id')
    expect(row).not_to have_key('chibi_weapon_svg_id')
  end
end
