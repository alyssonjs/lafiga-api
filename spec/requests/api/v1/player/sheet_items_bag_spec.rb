# frozen_string_literal: true

require 'rails_helper'

# BOLSAS (29/08): recipiente de PESO com capacidade em KG, equipável num slot
# próprio, com conteúdo por PONTEIRO (`bag_sheet_item_id`) — o mesmo desenho da
# aljava/montaria/carroça: o item nunca sai da ficha.
#
# As duas regras que só o servidor garante:
#   1. capacidade — duas abas abertas guardariam o mesmo último quilo;
#   2. ciclo — bolsa dentro de bolsa é permitido; A dentro de B dentro de A não.
RSpec.describe 'SheetItems — bolsas', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:character) { create(:character, user: user) }
  let!(:sheet) { create(:sheet, character: character) }

  # Bolsa DECLARADA no catálogo: category bag + capacity_kg. O peso do banco é
  # canônico em KG — a capacidade vive na mesma unidade.
  def bolsa_catalogo!(slug, capacidade_kg)
    Item.create!(api_index: slug, name: "Bolsa #{slug}", kind: 'gear', category: 'bag',
                 props: { 'capacity_kg' => capacidade_kg })
  end

  def linha!(nome, index: nil, peso_kg: nil, qty: 1)
    Item.create!(api_index: index, name: nome, kind: 'gear', weight_kg: peso_kg) if index && peso_kg && !Item.exists?(api_index: index)
    SheetItem.create!(sheet: sheet, item_name: nome, item_index: index, category: 'Itens Gerais',
                      quantity: qty, source: 'test')
  end

  def guardar(item, bolsa)
    post "/api/v1/player/sheet_items/#{item.id}/stow_in_bag",
         params: { bag_id: bolsa&.id }, headers: headers, as: :json
  end

  describe 'guardar e tirar' do
    it 'grava o PONTEIRO e devolve o item com ele' do
      bolsa_catalogo!('bolsa-teste', 10)
      bolsa = linha!('Bolsa de Viagem', index: 'bolsa-teste')
      corda = linha!('Corda comum')

      guardar(corda, bolsa)

      expect(response).to have_http_status(:ok), response.body
      expect(corda.reload.stored_in_bag_id).to eq(bolsa.id)
      expect(response.parsed_body.dig('sheet_item', 'props', 'bag_sheet_item_id')).to eq(bolsa.id)
    end

    it 'bag_id nulo tira da bolsa' do
      bolsa_catalogo!('bolsa-t2', 10)
      bolsa = linha!('Bolsa', index: 'bolsa-t2')
      corda = linha!('Corda comum')
      guardar(corda, bolsa)

      guardar(corda, nil)

      expect(corda.reload.stored_in_bag_id).to be_nil
    end

    it 'destino que NÃO é bolsa recusa' do
      corda = linha!('Corda comum')
      outra = linha!('Tocha simples')

      guardar(corda, outra)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'capacidade em KG (o servidor soma, não o cliente)' do
    it 'recusa quando o conteúdo passa do teto' do
      bolsa_catalogo!('bolsa-2kg', 2)
      bolsa = linha!('Bolsa Pequena', index: 'bolsa-2kg')
      ferro = linha!('Barra de Ferro', index: 'barra-ferro', peso_kg: 1.5)
      ouro = linha!('Barra de Ouro', index: 'barra-ouro', peso_kg: 1.0)
      guardar(ferro, bolsa)
      expect(response).to have_http_status(:ok), response.body

      guardar(ouro, bolsa)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/Não cabe/)
      expect(ouro.reload.stored_in_bag_id).to be_nil
    end

    it 'a QUANTIDADE multiplica o peso' do
      bolsa_catalogo!('bolsa-3kg', 3)
      bolsa = linha!('Bolsa Média', index: 'bolsa-3kg')
      flechas = linha!('Ponta de Ferro', index: 'ponta-ferro', peso_kg: 0.5, qty: 10)

      guardar(flechas, bolsa)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'bolsa SEM capacidade declarada guarda sem limite (manual do mestre)' do
      bolsa = linha!('Bolsa improvisada qualquer')
      pedra = linha!('Pedra enorme', index: 'pedra-enorme', peso_kg: 90)

      guardar(pedra, bolsa)

      expect(response).to have_http_status(:ok), response.body
    end
  end

  describe 'bolsa dentro de bolsa' do
    it 'aninhar é permitido (é o pedido)' do
      bolsa_catalogo!('bolsa-g', 20)
      bolsa_catalogo!('bolsa-p', 5)
      grande = linha!('Bolsa Grande', index: 'bolsa-g')
      pequena = linha!('Bolsa Pequena', index: 'bolsa-p')

      guardar(pequena, grande)

      expect(response).to have_http_status(:ok), response.body
      expect(pequena.reload.stored_in_bag_id).to eq(grande.id)
    end

    it 'CICLO recusa: A dentro de B dentro de A' do
      bolsa_catalogo!('bolsa-a', 20)
      bolsa_catalogo!('bolsa-b', 20)
      a = linha!('Bolsa A', index: 'bolsa-a')
      b = linha!('Bolsa B', index: 'bolsa-b')
      guardar(b, a)

      guardar(a, b)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/ciclo/i)
    end

    it 'bolsa dentro de si mesma recusa', :aggregate_failures do
      bolsa_catalogo!('bolsa-self', 20)
      a = linha!('Bolsa Própria', index: 'bolsa-self')

      guardar(a, a)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'apagar a bolsa liberta o conteúdo' do
    it 'o item volta solto, não some' do
      bolsa_catalogo!('bolsa-del', 10)
      bolsa = linha!('Bolsa Frágil', index: 'bolsa-del')
      corda = linha!('Corda comum')
      guardar(corda, bolsa)

      delete "/api/v1/player/sheet_items/#{bolsa.id}", headers: headers, as: :json

      expect(corda.reload.stored_in_bag_id).to be_nil
    end
  end

  describe 'slot e catálogo' do
    it '`bag` é slot válido (a bolsa equipada)' do
      bolsa_catalogo!('bolsa-eq', 10)
      bolsa = linha!('Bolsa Equipável', index: 'bolsa-eq')

      post "/api/v1/player/sheet_items/#{bolsa.id}/equip",
           params: { slot: 'bag' }, headers: headers, as: :json

      expect(response).to have_http_status(:ok), response.body
      expect(bolsa.reload.slot).to eq('bag')
    end

    it 'o balde `bags` serve a aba e SAI de gear (item numa aba só)' do
      bolsa_catalogo!('bolsa-aba', 10)
      # O balde gear vazio responde 404 — um item de controle prova a exclusão.
      # `category` preenchida: o balde gear usa NOT IN, que é NULL-unsafe —
      # gear com category nula nem aparece (comportamento pré-existente).
      Item.create!(api_index: 'lanterna-controle', name: 'Lanterna de Controle', kind: 'gear', category: 'lighting')

      get '/api/v1/public/equipment_list/bags'
      indices = response.parsed_body['equipment'].map { |r| r['index'] }
      expect(indices).to include('bolsa-aba')
      expect(response.parsed_body['equipment'].find { |r| r['index'] == 'bolsa-aba' }['bag_capacity_kg']).to eq(10)

      get '/api/v1/public/equipment_list/gear'
      expect(response.parsed_body['equipment'].map { |r| r['index'] }).not_to include('bolsa-aba')
    end
  end
end
