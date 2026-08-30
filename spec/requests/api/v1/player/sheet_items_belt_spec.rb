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
      # Nome NEUTRO de propósito: sem ele, este caso passaria pelo leitor de
      # nome e não provaria nada sobre a declaração do catálogo.
      Item.create!(api_index: 'aljava-b2', name: 'Porta-Virotes', kind: 'gear',
                   props: { 'equipment_slot' => 'quiver' })
      aljava = linha!('Porta-Virotes', index: 'aljava-b2')

      prender(ferramenta, cinto)
      expect(response).to have_http_status(:ok), response.body

      prender(aljava, cinto)
      expect(response).to have_http_status(:ok), response.body
    end

    it 'ALJAVA pelo NOME entra — ficha antiga nao declara recipiente' do
      cinto = linha!('Cinto', index: cinto_catalogo!('cinto-q1', livres: 1).api_index)
      # Sem catalogo nenhum: so o nome, como as fichas de antes de "recipiente".
      aljava = linha!('Aljava')

      prender(aljava, cinto)

      expect(response).to have_http_status(:ok), response.body
      expect(aljava.reload.stored_on_belt_id).to eq(cinto.id)
    end

    it 'QUALQUER recipiente de municao entra, mesmo sem "aljava" no nome' do
      cinto = linha!('Cinto', index: cinto_catalogo!('cinto-q2', livres: 1).api_index)
      # ⚠️ A chave canônica é `equipment_slot`, não `ammunition_container`:
      # é ela que o `EquipmentRules.ammunition_container_props` exige.
      Item.create!(api_index: 'bandoleira-q2', name: 'Bandoleira de Virotes', kind: 'gear',
                   props: { 'equipment_slot' => 'quiver', 'ammunition_capacity' => 20 })
      bandoleira = linha!('Bandoleira de Virotes', index: 'bandoleira-q2')

      prender(bandoleira, cinto)

      expect(response).to have_http_status(:ok), response.body
      expect(bandoleira.reload.stored_on_belt_id).to eq(cinto.id)
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

  # Tirar do cinto arruma na bolsa VESTIDA — é de lá que a mão tirou. Cair
  # solto era o comportamento e lia-se como perder o item de vista.
  describe 'soltar devolve à bolsa vestida' do
    def bolsa_vestida!(slug, capacidade_kg)
      Item.create!(api_index: slug, name: "Mochila #{slug}", kind: 'gear', category: 'bag',
                   props: { 'capacity_kg' => capacidade_kg })
      SheetItem.create!(sheet: sheet, item_name: 'Mochila', item_index: slug, category: 'Itens Gerais',
                        quantity: 1, source: 'test', equipped: true, slot: 'bag')
    end

    it 'o item volta PARA a bolsa vestida, nao para o chao' do
      mochila = bolsa_vestida!('mochila-s1', 15)
      cinto = linha!('Cinto', index: cinto_catalogo!('cinto-s1', livres: 1).api_index)
      catalogo!('adaga', 'Adaga', 'weapon')
      adaga = linha!('Adaga', index: 'adaga')
      prender(adaga, cinto)

      prender(adaga, nil)

      adaga.reload
      expect(adaga.stored_on_belt_id).to be_nil
      expect(adaga.stored_in_bag_id).to eq(mochila.id)
    end

    it 'sem bolsa vestida, continua a cair solto' do
      cinto = linha!('Cinto', index: cinto_catalogo!('cinto-s2', livres: 1).api_index)
      catalogo!('adaga', 'Adaga', 'weapon')
      adaga = linha!('Adaga', index: 'adaga')
      prender(adaga, cinto)

      prender(adaga, nil)

      expect(adaga.reload.stored_in_bag_id).to be_nil
    end

    it 'bolsa vestida SEM VAGA deixa cair solto — nao estoura o teto' do
      # Teto 1 kg, já com 1 kg dentro: a adaga de 1 kg não cabe de volta.
      mochila = bolsa_vestida!('mochila-s3', 1)
      Item.create!(api_index: 'tijolo-1kg-s3', name: 'Tijolo', kind: 'gear', weight_kg: 1.0)
      lastro = linha!('Tijolo', index: 'tijolo-1kg-s3')
      post "/api/v1/player/sheet_items/#{lastro.id}/stow_in_bag",
           params: { bag_id: mochila.id }, headers: headers, as: :json
      expect(response).to have_http_status(:ok), response.body

      cinto = linha!('Cinto', index: cinto_catalogo!('cinto-s3', livres: 1).api_index)
      Item.create!(api_index: 'adaga-1kg-s3', name: 'Adaga Pesada', kind: 'weapon', weight_kg: 1.0)
      adaga = linha!('Adaga Pesada', index: 'adaga-1kg-s3')
      prender(adaga, cinto)

      prender(adaga, nil)

      expect(response).to have_http_status(:ok), response.body
      expect(adaga.reload.stored_in_bag_id).to be_nil
    end
  end

  # SACAR: a arma do cinto vai para a mão e o que estava lá toma o lugar dela.
  # É UM movimento — meio dele deixaria duas armas na mesma mão.
  describe 'sacar do cinto para a mao' do
    def sacar(item, slot)
      post "/api/v1/player/sheet_items/#{item.id}/draw_from_belt",
           params: { slot: slot }, headers: headers, as: :json
    end

    it 'com a mao VAZIA, a arma sai do cinto e equipa' do
      cinto = linha!('Cinto', index: cinto_catalogo!('cinto-d1', livres: 2).api_index)
      catalogo!('adaga', 'Adaga', 'weapon')
      adaga = linha!('Adaga', index: 'adaga')
      prender(adaga, cinto)

      sacar(adaga, 'main_hand')

      expect(response).to have_http_status(:ok), response.body
      adaga.reload
      expect(adaga.equipped).to be(true)
      expect(adaga.slot).to eq('main_hand')
      expect(adaga.stored_on_belt_id).to be_nil
    end

    it 'com a mao OCUPADA, TROCA: a de la vai para o cinto que vagou' do
      cinto = linha!('Cinto', index: cinto_catalogo!('cinto-d2', livres: 1).api_index)
      catalogo!('adaga', 'Adaga', 'weapon')
      catalogo!('espada-d2', 'Espada', 'weapon')
      adaga = linha!('Adaga', index: 'adaga')
      espada = linha!('Espada', index: 'espada-d2')
      espada.update!(equipped: true, slot: 'main_hand')
      prender(adaga, cinto)

      sacar(adaga, 'main_hand')

      expect(response).to have_http_status(:ok), response.body
      adaga.reload
      espada.reload
      expect(adaga.slot).to eq('main_hand')
      expect(espada.equipped).to be(false)
      expect(espada.slot).to be_nil
      # O slot que a adaga largou tem exatamente uma vaga — a espada toma-a.
      expect(espada.stored_on_belt_id).to eq(cinto.id)
    end

    it 'o deslocado que NAO cabe no cinto desce para a bolsa vestida' do
      Item.create!(api_index: 'mochila-d3', name: 'Mochila', kind: 'gear', category: 'bag',
                   props: { 'capacity_kg' => 20 })
      mochila = SheetItem.create!(sheet: sheet, item_name: 'Mochila', item_index: 'mochila-d3',
                                  category: 'Itens Gerais', quantity: 1, source: 'test',
                                  equipped: true, slot: 'bag')
      cinto = linha!('Cinto', index: cinto_catalogo!('cinto-d3', livres: 1).api_index)
      catalogo!('adaga', 'Adaga', 'weapon')
      adaga = linha!('Adaga', index: 'adaga')
      # Escudo nao e arma/ferramenta/aljava: nao tem vocacao de slot livre.
      catalogo!('escudo-d3', 'Escudo', 'shield')
      escudo = linha!('Escudo', index: 'escudo-d3')
      escudo.update!(equipped: true, slot: 'off_hand')
      prender(adaga, cinto)

      sacar(adaga, 'off_hand')

      expect(response).to have_http_status(:ok), response.body
      escudo.reload
      expect(escudo.equipped).to be(false)
      expect(escudo.stored_on_belt_id).to be_nil
      expect(escudo.stored_in_bag_id).to eq(mochila.id)
    end

    it 'so saca o que esta NUM CINTO' do
      catalogo!('adaga', 'Adaga', 'weapon')
      solta = linha!('Adaga', index: 'adaga')

      sacar(solta, 'main_hand')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/não está preso num cinto/)
    end

    it 'so saca ARMA — a pocao do cinto nao vai para a mao' do
      cinto = linha!('Cinto', index: cinto_catalogo!('cinto-d5', livres: 1, consumiveis: 1).api_index)
      catalogo!('pocao-cura', 'Poção de Cura', 'consumable')
      pocao = linha!('Poção de Cura', index: 'pocao-cura')
      prender(pocao, cinto)

      sacar(pocao, 'main_hand')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/Só arma se empunha/)
    end

    it 'so saca para MAO — nao para a cabeca' do
      cinto = linha!('Cinto', index: cinto_catalogo!('cinto-d6', livres: 1).api_index)
      catalogo!('adaga', 'Adaga', 'weapon')
      adaga = linha!('Adaga', index: 'adaga')
      prender(adaga, cinto)

      sacar(adaga, 'helmet')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(adaga.reload.stored_on_belt_id).to eq(cinto.id)
    end
  end

  # O slot de consumível leva UMA unidade: é o frasco que a mão alcança, não a
  # caixa toda. Sem isto, um slot escondia a pilha inteira e beber esvaziava
  # tudo de uma vez.
  describe 'consumivel: uma unidade por slot' do
    def pilhas(nome)
      sheet.sheet_items.reload.where(item_name: nome)
           .map { |si| [si.quantity, si.stored_on_belt_id] }.sort_by(&:first)
    end

    it 'prender uma pilha leva SO UMA — o resto fica onde estava' do
      cinto = linha!('Cinto', index: cinto_catalogo!('cinto-c1', livres: 1, consumiveis: 2).api_index)
      catalogo!('pocao-cura', 'Poção de Cura', 'consumable')
      pocoes = linha!('Poção de Cura', index: 'pocao-cura', qty: 3)

      prender(pocoes, cinto)

      expect(response).to have_http_status(:ok), response.body
      expect(pilhas('Poção de Cura')).to eq([[1, cinto.id], [2, nil]])
    end

    it 'dois slots levam DUAS linhas de um — nao uma de dois' do
      cinto = linha!('Cinto', index: cinto_catalogo!('cinto-c2', livres: 1, consumiveis: 2).api_index)
      catalogo!('pocao-cura', 'Poção de Cura', 'consumable')
      pocoes = linha!('Poção de Cura', index: 'pocao-cura', qty: 3)
      prender(pocoes, cinto)

      prender(pocoes.reload, cinto)

      expect(response).to have_http_status(:ok), response.body
      # Duas linhas de 1 no cinto (dois slots) + 1 fora.
      expect(pilhas('Poção de Cura')).to eq([[1, cinto.id], [1, cinto.id], [1, nil]])
    end

    it 'o terceiro nao entra: dois slots, duas pocoes' do
      cinto = linha!('Cinto', index: cinto_catalogo!('cinto-c3', livres: 1, consumiveis: 2).api_index)
      catalogo!('pocao-cura', 'Poção de Cura', 'consumable')
      pocoes = linha!('Poção de Cura', index: 'pocao-cura', qty: 5)
      prender(pocoes, cinto)
      prender(pocoes.reload, cinto)

      prender(pocoes.reload, cinto)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(%r{2/2 slots de consumível})
    end

    it 'ARMA vai INTEIRA — nao empilha, nao se divide' do
      cinto = linha!('Cinto', index: cinto_catalogo!('cinto-c4', livres: 1).api_index)
      catalogo!('adaga', 'Adaga', 'weapon')
      adagas = linha!('Adaga', index: 'adaga', qty: 2)

      prender(adagas, cinto)

      expect(pilhas('Adaga')).to eq([[2, cinto.id]])
    end

    it 'soltar FUNDE de volta na pilha da bolsa — nao deixa duas linhas' do
      Item.create!(api_index: 'mochila-c5', name: 'Mochila', kind: 'gear', category: 'bag',
                   props: { 'capacity_kg' => 20 })
      mochila = SheetItem.create!(sheet: sheet, item_name: 'Mochila', item_index: 'mochila-c5',
                                  category: 'Itens Gerais', quantity: 1, source: 'test',
                                  equipped: true, slot: 'bag')
      cinto = linha!('Cinto', index: cinto_catalogo!('cinto-c5', livres: 1, consumiveis: 1).api_index)
      catalogo!('pocao-cura', 'Poção de Cura', 'consumable')
      pocoes = linha!('Poção de Cura', index: 'pocao-cura', qty: 3)
      post "/api/v1/player/sheet_items/#{pocoes.id}/stow_in_bag",
           params: { bag_id: mochila.id }, headers: headers, as: :json
      prender(pocoes.reload, cinto)
      presa = sheet.sheet_items.reload.find { |si| si.stored_on_belt_id == cinto.id }

      prender(presa, nil)

      # Uma linha só, de volta a 3 — e na bolsa vestida.
      restantes = sheet.sheet_items.reload.where(item_name: 'Poção de Cura')
      expect(restantes.map(&:quantity)).to eq([3])
      expect(restantes.first.stored_in_bag_id).to eq(mochila.id)
    end
  end
end
