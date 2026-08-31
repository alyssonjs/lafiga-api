# frozen_string_literal: true

require 'rails_helper'

# SLOTS EXTERNOS da bolsa: o bolso de fora da mochila.
#
# Mesma mecânica de contagem do cinto, com UMA diferença que é o pedido
# inteiro: o slot externo NÃO tem vocação. Leva o que couber — arma, corda,
# poção, tocha —, e por isso a declaração é um número só (`bag_slots`) e não
# um par livre/consumível.
#
# ⚠️ Preso POR FORA não é guardado DENTRO: ponteiro próprio, conta vaga e não
# quilo. É o que permite pendurar a corda na mochila cheia.
RSpec.describe 'SheetItems — slots externos da bolsa', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:character) { create(:character, user: user) }
  let!(:sheet) { create(:sheet, character: character) }

  def bolsa_catalogo!(slug, slots:, capacidade_kg: 10)
    Item.create!(api_index: slug, name: "Bolsa #{slug}", kind: 'gear', category: 'bag',
                 props: { 'capacity_kg' => capacidade_kg, 'bag_slots' => slots })
  end

  def linha!(nome, index: nil, qty: 1)
    SheetItem.create!(sheet: sheet, item_name: nome, item_index: index, category: 'Itens Gerais',
                      quantity: qty, source: 'test')
  end

  def pendurar(item, bolsa)
    post "/api/v1/player/sheet_items/#{item.id}/stow_on_bag_slot",
         params: { bag_id: bolsa&.id }, headers: headers, as: :json
  end

  describe 'pendurar e soltar' do
    it 'grava o ponteiro do slot externo' do
      mochila = linha!('Mochila', index: bolsa_catalogo!('mochila-s1', slots: 2).api_index)
      corda = linha!('Corda')

      pendurar(corda, mochila)

      expect(response).to have_http_status(:ok), response.body
      expect(corda.reload.stored_on_bag_slot_id).to eq(mochila.id)
    end

    it 'QUALQUER item entra — o bolso de fora nao tem vocacao' do
      mochila = linha!('Mochila', index: bolsa_catalogo!('mochila-s2', slots: 4).api_index)
      Item.create!(api_index: 'adaga-s2', name: 'Adaga', kind: 'weapon')
      Item.create!(api_index: 'pocao-s2', name: 'Poção', kind: 'consumable')
      Item.create!(api_index: 'corda-s2', name: 'Corda', kind: 'gear')

      [linha!('Adaga', index: 'adaga-s2'),
       linha!('Poção', index: 'pocao-s2'),
       linha!('Corda', index: 'corda-s2')].each do |it|
        pendurar(it, mochila)
        expect(response).to have_http_status(:ok), response.body
      end
    end

    it 'bag_id nulo solta' do
      mochila = linha!('Mochila', index: bolsa_catalogo!('mochila-s3', slots: 1).api_index)
      corda = linha!('Corda')
      pendurar(corda, mochila)

      pendurar(corda, nil)

      expect(corda.reload.stored_on_bag_slot_id).to be_nil
    end

    it 'bolsa SEM slots declarados recusa' do
      simples = linha!('Bolsa Simples', index: bolsa_catalogo!('mochila-s4', slots: 0).api_index)
      corda = linha!('Corda')

      pendurar(corda, simples)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/não tem slots externos/)
    end
  end

  describe 'contagem de vagas' do
    it 'esgotadas as vagas, o proximo recusa' do
      mochila = linha!('Mochila', index: bolsa_catalogo!('mochila-v1', slots: 1).api_index)
      pendurar(linha!('Corda'), mochila)

      pendurar(linha!('Tocha'), mochila)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(%r{1/1 slots externos})
    end

    it 'a bolsa nao se pendura em si mesma' do
      mochila = linha!('Mochila', index: bolsa_catalogo!('mochila-v2', slots: 2).api_index)

      pendurar(mochila, mochila)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'ciclo barrado: A pendurada em B e B pendurada em A' do
      slug = bolsa_catalogo!('mochila-v3', slots: 2).api_index
      a = linha!('Bolsa A', index: slug)
      b = linha!('Bolsa B', index: slug)
      pendurar(a, b)

      pendurar(b, a)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/ciclo/)
    end
  end

  describe 'os ponteiros sao exclusivos' do
    it 'pendurar por FORA tira de DENTRO' do
      mochila = linha!('Mochila', index: bolsa_catalogo!('mochila-e1', slots: 2).api_index)
      corda = linha!('Corda')
      post "/api/v1/player/sheet_items/#{corda.id}/stow_in_bag",
           params: { bag_id: mochila.id }, headers: headers, as: :json
      expect(corda.reload.stored_in_bag_id).to eq(mochila.id)

      pendurar(corda, mochila)

      corda.reload
      expect(corda.stored_on_bag_slot_id).to eq(mochila.id)
      expect(corda.stored_in_bag_id).to be_nil
    end

    it 'guardar DENTRO tira do bolso de fora' do
      mochila = linha!('Mochila', index: bolsa_catalogo!('mochila-e2', slots: 2).api_index)
      corda = linha!('Corda')
      pendurar(corda, mochila)

      post "/api/v1/player/sheet_items/#{corda.id}/stow_in_bag",
           params: { bag_id: mochila.id }, headers: headers, as: :json

      corda.reload
      expect(corda.stored_in_bag_id).to eq(mochila.id)
      expect(corda.stored_on_bag_slot_id).to be_nil
    end
  end

  describe 'catálogo e limpeza' do
    it 'a linha da bolsa viaja com a contagem de slots' do
      mochila = linha!('Mochila', index: bolsa_catalogo!('mochila-c1', slots: 3).api_index)
      corda = linha!('Corda')

      pendurar(corda, mochila)

      linha = response.parsed_body['sheet_items'].find { |i| i['id'] == mochila.id }
      expect(linha['bag_slot_count']).to eq(3)
    end

    it 'apagar a bolsa SOLTA o que estava pendurado' do
      mochila = linha!('Mochila', index: bolsa_catalogo!('mochila-c2', slots: 1).api_index)
      corda = linha!('Corda')
      pendurar(corda, mochila)

      mochila.destroy!

      expect(corda.reload.stored_on_bag_slot_id).to be_nil
    end
  end
end
