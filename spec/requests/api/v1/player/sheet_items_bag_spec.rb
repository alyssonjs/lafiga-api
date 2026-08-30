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

  def guardar(item, bolsa, quantidade: nil)
    post "/api/v1/player/sheet_items/#{item.id}/stow_in_bag",
         params: { bag_id: bolsa&.id }.merge(quantidade ? { quantity: quantidade } : {}),
         headers: headers, as: :json
  end

  # O que a ficha tem com aquele nome, e onde está cada pilha.
  def pilhas(nome)
    sheet.sheet_items.reload.where(item_name: nome).map { |si| [si.quantity, si.stored_in_bag_id] }.sort_by(&:first)
  end

  describe 'guardar e tirar' do
    it 'grava o PONTEIRO e devolve o item com ele' do
      bolsa_catalogo!('bolsa-teste', 10)
      bolsa = linha!('Bolsa de Viagem', index: 'bolsa-teste')
      corda = linha!('Corda comum')

      guardar(corda, bolsa)

      expect(response).to have_http_status(:ok), response.body
      expect(corda.reload.stored_in_bag_id).to eq(bolsa.id)
      # A resposta é o INVENTÁRIO: um movimento parcial toca duas linhas, e a
      # original pode nem sobreviver (pilha inteira fundida numa gémea).
      linha = response.parsed_body['sheet_items'].find { |i| i['id'] == corda.id }
      expect(linha.dig('props', 'bag_sheet_item_id')).to eq(bolsa.id)
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

  # Pilhas: mover 3 das 10 flechas é dividir a linha, não etiquetá-la inteira.
  describe 'quantidade parcial' do
    it 'sem `quantity`, move a pilha INTEIRA (o que sempre fez)' do
      bolsa_catalogo!('bolsa-q1', 50)
      bolsa = linha!('Bolsa', index: 'bolsa-q1')
      flechas = linha!('Flecha', qty: 10)

      guardar(flechas, bolsa)

      expect(pilhas('Flecha')).to eq([[10, bolsa.id]])
    end

    it 'com `quantity`, DIVIDE: parte vai, o resto fica onde estava' do
      bolsa_catalogo!('bolsa-q2', 50)
      bolsa = linha!('Bolsa', index: 'bolsa-q2')
      flechas = linha!('Flecha', qty: 10)

      guardar(flechas, bolsa, quantidade: 3)

      expect(response).to have_http_status(:ok), response.body
      expect(pilhas('Flecha')).to eq([[3, bolsa.id], [7, nil]])
    end

    it 'funde na pilha gemea que ja esta na bolsa, em vez de criar segunda linha' do
      bolsa_catalogo!('bolsa-q3', 50)
      bolsa = linha!('Bolsa', index: 'bolsa-q3')
      flechas = linha!('Flecha', qty: 10)
      guardar(flechas, bolsa, quantidade: 4)

      guardar(flechas, bolsa, quantidade: 2)

      expect(pilhas('Flecha')).to eq([[4, nil], [6, bolsa.id]])
    end

    it 'move parte de uma bolsa DIRETO para outra' do
      bolsa_catalogo!('bolsa-q4', 50)
      origem = linha!('Bolsa A', index: 'bolsa-q4')
      destino = linha!('Bolsa B', index: 'bolsa-q4')
      flechas = linha!('Flecha', qty: 10)
      guardar(flechas, origem)

      guardar(flechas, destino, quantidade: 6)

      expect(pilhas('Flecha')).to eq([[4, origem.id], [6, destino.id]])
    end

    it 'quantidade acima do disponivel recusa' do
      bolsa_catalogo!('bolsa-q5', 50)
      bolsa = linha!('Bolsa', index: 'bolsa-q5')
      flechas = linha!('Flecha', qty: 10)

      guardar(flechas, bolsa, quantidade: 11)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/Disponível: 10/)
      expect(pilhas('Flecha')).to eq([[10, nil]])
    end

    it 'quantidade zero ou negativa recusa' do
      bolsa_catalogo!('bolsa-q6', 50)
      bolsa = linha!('Bolsa', index: 'bolsa-q6')
      flechas = linha!('Flecha', qty: 10)

      guardar(flechas, bolsa, quantidade: 0)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(pilhas('Flecha')).to eq([[10, nil]])
    end

    it 'a CAPACIDADE conta so o que vai mover, nao a pilha toda' do
      bolsa_catalogo!('bolsa-q7', 3)
      bolsa = linha!('Bolsa', index: 'bolsa-q7')
      # 10 tijolos de 1 kg: a pilha inteira nao cabe num teto de 3 kg, 3 cabem.
      tijolos = linha!('Tijolo', index: 'tijolo-1kg', peso_kg: 1.0, qty: 10)

      guardar(tijolos, bolsa, quantidade: 3)
      expect(response).to have_http_status(:ok), response.body

      guardar(sheet.sheet_items.reload.find_by(item_name: 'Tijolo', quantity: 7), bolsa, quantidade: 1)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/Não cabe/)
    end
  end

  # A conta da tela e a do servidor tem de sair do MESMO numero. Enquanto o
  # inventario nao mandava peso, o front lia `props_json['weight_lb']` — prop
  # que so existe em quem a gravou na compra — e a barra da bolsa dizia 10 kg
  # onde o servidor somava 15: a tela recusava o que ela propria dizia caber.
  describe 'peso na resposta do inventario' do
    it 'manda `weight_lb` mesmo sem a prop gravada na linha' do
      bolsa_catalogo!('bolsa-w1', 15)
      bolsa = linha!('Bolsa', index: 'bolsa-w1')
      # Corda de 5 kg no CATALOGO, e nada em props_json.
      corda = linha!('Corda 15m', index: 'corda-15m', peso_kg: 5.0, qty: 2)
      expect(corda.props_json.to_h['weight_lb']).to be_nil

      guardar(corda, bolsa)

      linha = response.parsed_body['sheet_items'].find { |i| i['id'] == corda.id }
      # Convencao do LIVRO: kg × 2.
      expect(linha['weight_lb']).to eq(10.0)
    end

    it 'o peso enviado e o MESMO que valida a capacidade' do
      bolsa_catalogo!('bolsa-w2', 15)
      bolsa = linha!('Bolsa', index: 'bolsa-w2')
      corda = linha!('Corda 15m', index: 'corda-15m', peso_kg: 5.0, qty: 2)
      guardar(corda, bolsa)

      # 10 kg dentro, teto 15: um tijolo de 6 kg nao cabe, um de 4 cabe.
      pesado = linha!('Bigorna', index: 'bigorna-6kg', peso_kg: 6.0)
      guardar(pesado, bolsa)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/16\.0 kg num teto de 15\.0 kg/)

      leve = linha!('Tijolo', index: 'tijolo-4kg', peso_kg: 4.0)
      guardar(leve, bolsa)
      expect(response).to have_http_status(:ok), response.body
    end
  end
end
