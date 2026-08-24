# frozen_string_literal: true

require 'rails_helper'

# UNIDADE DE PESO na fronteira catalogo -> front.
#
# O banco guarda KG (PHB pt-BR: espada longa 1,5 kg). O front inteiro rotula e
# grava LIBRAS ("X lb" no compendio; `props.weight_lb` na bolsa). Ate 24/08 o
# serializer mandava o kg CRU no campo `weight`, e a carga do personagem e da
# carroca ficavam sub-contadas ~2x.
#
# A conversao usa o fator do LIVRO (1 lb = 0,5 kg — a traducao pt-BR converteu
# assim), nao o fisico 2.20462: espada longa tem de dar 3 lb, nao 3,31.
RSpec.describe 'Api::V1::Public::EquipmentController unidades de peso', type: :request do
  let!(:ferramenta) do
    Item.create!(name: 'Spec Ferramentas de Ferreiro', api_index: "spec-ferreiro-#{SecureRandom.hex(3)}",
                 kind: 'tool', category: 'artisan', weight_kg: 4.0)
  end
  let!(:arma) do
    Item.create!(name: 'Spec Espada Longa', api_index: "spec-espada-#{SecureRandom.hex(3)}",
                 kind: 'weapon', category: 'martial',
                 weight_kg: 1.5,
                 props: { 'type' => 'melee', 'damage_die' => '1d8', 'damage_type' => 'cortante' })
  end
  let!(:sem_peso) do
    Item.create!(name: 'Spec Pena', api_index: "spec-pena-#{SecureRandom.hex(3)}",
                 kind: 'tool', category: 'artisan')
  end

  def weight_of(category, api_index)
    get "/api/v1/public/equipment_list/#{category}"
    expect(response).to have_http_status(:ok)
    row = Array(response.parsed_body['equipment']).find { |e| e['index'] == api_index }
    expect(row).not_to be_nil
    row['weight']
  end

  it 'ferramenta: 4 kg do banco viram 8 lb no payload' do
    expect(weight_of('tools', ferramenta.api_index)).to eq(8.0)
  end

  it 'arma: espada longa 1,5 kg vira os 3 lb da tabela do livro' do
    expect(weight_of('martial-weapons', arma.api_index)).to eq(3.0)
  end

  it 'item sem peso pesa 0 — contrato antigo do EquipmentRules (piso 0.0, nunca nil)' do
    # O front esconde peso quando `weight > 0` e falso, entao 0.0 e inocuo.
    expect(weight_of('tools', sem_peso.api_index)).to eq(0.0)
  end
end
