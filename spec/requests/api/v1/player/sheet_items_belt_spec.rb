# frozen_string_literal: true

require 'rails_helper'

# CINTOS (30/08): recipiente de SLOTS, não de peso. O criador declara no
# catálogo quantos slots LIVRES (arma, ferramenta, aljava — coisas de sacar) e
# quantos de CONSUMÍVEL o cinto oferece. Mesma família da bolsa: o item nunca
# sai da ficha, a localização é o ponteiro `belt_sheet_item_id`.
#
# A regra do PHB que o slot livre codifica: arma no cinto está EQUIPADA no
# personagem mas fora das mãos — sacá-la é a interação livre do turno.
RSpec.describe 'SheetItems — cintos', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:character) { create(:character, user: user) }
  let!(:sheet) { create(:sheet, character: character) }

  def cinto_catalogo!(slug, livres:, consumiveis: 0)
    Item.create!(api_index: slug, name: "Cinto #{slug}", kind: 'gear', category: 'belt',
                 props: { 'belt_free_slots' => livres, 'belt_consumable_slots' => consumiveis })
  end

  def catalogo!(slug, nome, kind)
    Item.find_by(api_index: slug) || Item.create!(api_index: slug, name: nome, kind: kind)
  end

  def linha!(nome, index: nil, qty: 1)
    SheetItem.create!(sheet: sheet, item_name: nome, item_index: index, category: 'Itens Gerais',
                      quantity: qty, source: 'test')
  end

  def prender(item, cinto)
    post "/api/v1/player/sheet_items/#{item.id}/stow_on_belt",
         params: { belt_id: cinto&.id }, headers: headers, as: :json
  end

  describe 'prender e soltar' do
    it 'ARMA entra em slot livre e grava o ponteiro' do
      cinto = linha!('Cinto de Couro', index: cinto_catalogo!('cinto-b1', livres: 2).api_index)
      catalogo!('adaga', 'Adaga', 'weapon')
      adaga = linha!('Adaga', index: 'adaga')

      prender(adaga, cinto)

      expect(response).to have_http_status(:ok), response.body
      expect(adaga.reload.stored_on_belt_id).to eq(cinto.id)
    end

    it 'FERRAMENTA e ALJAVA também são de slot livre' do
      cinto = linha!('Cinto', index: cinto_catalogo!('cinto-b2', livres: 2).api_index)
      catalogo!('kit-ladrao', 'Ferramentas de Ladrão', 'tool')
      ferramenta = linha!('Ferramentas de Ladrão', index: 'kit-ladrao')
      Item.create!(api_index: 'aljava-b2', name: 'Aljava', kind: 'gear',
                   props: { 'equip_slot' => 'quiver', 'ammunition_container' => true })
      aljava = linha!('Aljava', index: 'aljava-b2')

      prender(ferramenta, cinto)
      expect(response).to have_http_status(:ok), response.body

      prender(aljava, cinto)
      expect(response).to have_http_status(:ok), response.body
    end

    it 'CONSUMÍVEL só entra se o cinto declarar slots de consumível' do
      so_livres = linha!('Cinto A', index: cinto_catalogo!('cinto-b3', livres: 2).api_index)
      catalogo!('pocao-cura', 'Poção de Cura', 'consumable')
      pocao = linha!('Poção de Cura', index: 'pocao-cura')

      prender(pocao, so_livres)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/não tem slots desse tipo/)
    end

    it 'belt_id nulo solta' do
      cinto = linha!('Cinto', index: cinto_catalogo!('cinto-b4', livres: 1).api_index)
      catalogo!('adaga', 'Adaga', 'weapon')
      adaga = linha!('Adaga', index: 'adaga')
      prender(adaga, cinto)

      prender(adaga, nil)

      expect(adaga.reload.stored_on_belt_id).to be_nil
    end

    it 'o que nao e arma/ferramenta/aljava/consumivel nao entra' do
      cinto = linha!('Cinto', index: cinto_catalogo!('cinto-b5', livres: 2, consumiveis: 2).api_index)
      catalogo!('corda-b5', 'Corda', 'gear')
      corda = linha!('Corda', index: 'corda-b5')

      prender(corda, cinto)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/Só arma, ferramenta, aljava ou consumível/)
    end
  end

  describe 'contagem de vagas por vocação' do
    it 'slots livres esgotados recusam a proxima arma — mas nao o consumivel' do
      cinto = linha!('Cinto', index: cinto_catalogo!('cinto-b6', livres: 1, consumiveis: 1).api_index)
      catalogo!('adaga', 'Adaga', 'weapon')
      catalogo!('machado-b6', 'Machado', 'weapon')
      catalogo!('pocao-cura', 'Poção de Cura', 'consumable')
      prender(linha!('Adaga', index: 'adaga'), cinto)

      prender(linha!('Machado', index: 'machado-b6'), cinto)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(%r{1/1 slots livres})

      prender(linha!('Poção de Cura', index: 'pocao-cura'), cinto)
      expect(response).to have_http_status(:ok), response.body
    end

    it 'cinto nao se prende em si mesmo' do
      cinto = linha!('Cinto', index: cinto_catalogo!('cinto-b7', livres: 1).api_index)

      prender(cinto, cinto)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'catálogo no inventário' do
    it 'a linha do cinto viaja com os slots declarados' do
      cinto = linha!('Cinto', index: cinto_catalogo!('cinto-b8', livres: 3, consumiveis: 2).api_index)
      catalogo!('adaga', 'Adaga', 'weapon')
      adaga = linha!('Adaga', index: 'adaga')

      prender(adaga, cinto)

      linha_cinto = response.parsed_body['sheet_items'].find { |i| i['id'] == cinto.id }
      expect(linha_cinto['belt_slot_props']).to eq({ 'free' => 3, 'consumable' => 2 })
    end

    it 'apagar o cinto SOLTA o que estava preso' do
      cinto = linha!('Cinto', index: cinto_catalogo!('cinto-b9', livres: 1).api_index)
      catalogo!('adaga', 'Adaga', 'weapon')
      adaga = linha!('Adaga', index: 'adaga')
      prender(adaga, cinto)

      cinto.destroy!

      expect(adaga.reload.stored_on_belt_id).to be_nil
    end

    it 'prender tira da BOLSA — os ponteiros sao exclusivos' do
      Item.create!(api_index: 'bolsa-b10', name: 'Bolsa', kind: 'gear', category: 'bag',
                   props: { 'capacity_kg' => 10 })
      bolsa = linha!('Bolsa', index: 'bolsa-b10')
      cinto = linha!('Cinto', index: cinto_catalogo!('cinto-b10', livres: 1).api_index)
      catalogo!('adaga', 'Adaga', 'weapon')
      adaga = linha!('Adaga', index: 'adaga')
      post "/api/v1/player/sheet_items/#{adaga.id}/stow_in_bag",
           params: { bag_id: bolsa.id }, headers: headers, as: :json

      prender(adaga, cinto)

      adaga.reload
      expect(adaga.stored_on_belt_id).to eq(cinto.id)
      expect(adaga.stored_in_bag_id).to be_nil
    end
  end
end
