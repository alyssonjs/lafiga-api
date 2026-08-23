# frozen_string_literal: true

require 'rails_helper'

# A aba "Equipamentos" do compendio era uma casca: dizia "catalogo mundano
# indisponivel" e nao havia UM item de transporte no banco. Veiculo e arreio
# vivem como `kind: gear` + categoria propria — mesmo carve-out do `pack` e do
# `instrument`, sem tocar no enum de `kind`.
RSpec.describe 'Api::V1::Public::EquipmentController veiculos', type: :request do
  let!(:terrestre) do
    Item.create!(name: 'Spec Carroça', api_index: "spec-carroca-#{SecureRandom.hex(3)}",
                 kind: 'gear', category: 'vehicle_land', weight_kg: 100)
  end
  let!(:aquatico) do
    Item.create!(name: 'Spec Veleiro', api_index: "spec-veleiro-#{SecureRandom.hex(3)}",
                 kind: 'gear', category: 'vehicle_water', props: { 'speed_kmh' => 3.0 })
  end
  let!(:arreio) do
    Item.create!(name: 'Spec Sela', api_index: "spec-sela-#{SecureRandom.hex(3)}",
                 kind: 'gear', category: 'tack', weight_kg: 7.5)
  end
  let!(:gear_comum) do
    Item.create!(name: 'Spec Corda', api_index: "spec-corda-#{SecureRandom.hex(3)}",
                 kind: 'gear', category: 'gear')
  end

  def indexes_for(category)
    get "/api/v1/public/equipment_list/#{category}"
    expect(response).to have_http_status(:ok)
    Array(response.parsed_body['equipment']).map { |e| e['index'] }
  end

  it 'os tres grupos vem na mesma aba' do
    idx = indexes_for('vehicles')

    expect(idx).to include(terrestre.api_index, aquatico.api_index, arreio.api_index)
  end

  it 'REGRESSAO: transporte nao aparece tambem em Equipamento' do
    idx = indexes_for('gear')

    expect(idx).to include(gear_comum.api_index)
    expect(idx).not_to include(terrestre.api_index, aquatico.api_index, arreio.api_index)
  end

  it 'a `gear_category` distingue os tres grupos para o front agrupar' do
    get '/api/v1/public/equipment_list/vehicles'
    rows = Array(response.parsed_body['equipment'])

    cats = rows.select { |r| [terrestre.api_index, aquatico.api_index, arreio.api_index].include?(r['index']) }
                .map { |r| r['gear_category'] }
    expect(cats).to match_array(%w[vehicle_land vehicle_water tack])
  end

  it 'o rotulo da categoria diz "vehicles", nao "Adventuring Gear"' do
    get '/api/v1/public/equipment_list/vehicles'
    idx = Array(response.parsed_body['equipment']).map { |e| e.dig('equipment_category', 'index') }.uniq

    expect(idx).to eq(['vehicles'])
  end

  it 'aceita o alias em portugues' do
    expect(indexes_for('veiculos')).to include(terrestre.api_index)
  end

  it 'entra no snapshot da bolsa (senao sumiria do modal Adicionar item)' do
    get '/api/v1/public/equipment_catalog_snapshot'
    idx = Array(response.parsed_body.dig('by_category', 'vehicles')).map { |e| e['index'] }

    expect(idx).to include(terrestre.api_index, aquatico.api_index, arreio.api_index)
  end
end
