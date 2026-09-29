# frozen_string_literal: true

require 'rails_helper'

# A oficina da ficha, do lado do MESTRE: ensinar receita, iniciar, contar os
# dias, concluir e cancelar. Toda resposta traz o estado inteiro (`crafting`).
RSpec.describe 'Api::V1::Admin::SheetCrafting', type: :request do
  let(:dm_role) { Role.find_or_create_by!(name: 'DM') }
  let(:dm) { create(:user, role: dm_role) }
  let(:dono) { create(:user) }
  let(:headers) { bearer_headers_for(dm).merge('Content-Type' => 'application/json') }
  let(:sheet) { create(:sheet, character: create(:character, user: dono)) }
  def corpo = JSON.parse(response.body)
  let(:base) { "/api/v1/admin/sheets/#{sheet.id}/crafting" }

  let(:pocao) { oficina_item('alq-pocao-cura', 'Poção de Cura', kind: 'consumable', category: 'potion') }
  let(:extrato) { oficina_item('mat-extrato', 'Extrato Vegetal', props: { 'unit' => 'ml' }) }
  let(:receita) { oficina_receita(produto: pocao, ingredientes: [[extrato, 30, 'ml']], days: 1.5) }

  def ensina = post("#{base}/recipes", params: { recipe_id: receita.id }.to_json, headers: headers)
  def inicia(extra = {})
    post "#{base}/crafts", params: { craft: { recipe_id: receita.id, quantity: 2 }.merge(extra) }.to_json, headers: headers
  end

  it '⚠️ só o Mestre escreve' do
    post "#{base}/recipes", params: { recipe_id: receita.id }.to_json,
                            headers: bearer_headers_for(dono).merge('Content-Type' => 'application/json')
    expect(response).to have_http_status(:forbidden)
  end

  describe 'receitas conhecidas' do
    it 'ensinar devolve a oficina com a receita', :aggregate_failures do
      ensina
      expect(response).to have_http_status(:created)
      expect(corpo.dig('crafting', 'recipes').map { |r| r['id'] }).to eq([receita.id])
    end

    it 'ensinar de novo não duplica' do
      2.times { ensina }
      expect(sheet.sheet_known_recipes.count).to eq(1)
    end

    it 'esquecer tira da lista' do
      ensina
      delete "#{base}/recipes/#{receita.id}", headers: headers
      expect(corpo.dig('crafting', 'recipes')).to eq([])
    end
  end

  describe 'iniciar' do
    it '⚠️ recusa receita que o personagem não conhece' do
      inicia
      expect(response).to have_http_status(:unprocessable_entity)
      expect(corpo['errors']).to include('não conhece')
    end

    it 'dias = os da receita × a quantidade; NADA sai da bolsa', :aggregate_failures do
      ensina
      na_bolsa(sheet, extrato, 100)
      inicia

      expect(response).to have_http_status(:created)
      c = corpo.dig('crafting', 'crafts').first
      expect(c).to include('id' => corpo['craft_id'], 'product_name' => 'Poção de Cura', 'quantity' => 2,
                           'days_required' => 3.0, 'days_worked' => 0.0, 'status' => 'in_progress', 'materials_ok' => true)
      expect(sheet.sheet_items.where(item_id: extrato.id).sum(:quantity)).to eq(100)
    end

    it 'o Mestre pode cravar os dias' do
      ensina
      inicia(days_required: 10)
      expect(corpo.dig('crafting', 'crafts', 0, 'days_required')).to eq(10.0)
    end
  end

  describe 'contar dias, concluir, cancelar' do
    let(:craft_id) do
      ensina
      inicia
      corpo['craft_id']
    end

    it 'PATCH parcial conta os dias sem mexer no resto', :aggregate_failures do
      patch "#{base}/crafts/#{craft_id}", params: { craft: { days_worked: 2.5 } }.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(corpo.dig('crafting', 'crafts', 0)).to include('days_worked' => 2.5, 'days_required' => 3.0)
    end

    it 'concluir sem material responde 422 com o que falta' do
      post "#{base}/crafts/#{craft_id}/complete", headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(corpo['missing']).to eq([{ 'name' => 'Extrato Vegetal', 'unit' => 'ml', 'missing' => 60 }])
    end

    it 'concluir desconta e entrega o produto', :aggregate_failures do
      na_bolsa(sheet, extrato, 70)
      post "#{base}/crafts/#{craft_id}/complete", headers: headers

      expect(response).to have_http_status(:ok)
      expect(corpo.dig('crafting', 'crafts', 0, 'status')).to eq('done')
      expect(sheet.sheet_items.where(item_id: extrato.id).sum(:quantity)).to eq(10)
      expect(sheet.sheet_items.find_by(item_id: pocao.id)).to have_attributes(quantity: 2, source: 'crafted')
    end

    it 'com `force` conclui mesmo faltando' do
      post "#{base}/crafts/#{craft_id}/complete", params: { force: true }.to_json, headers: headers
      expect(corpo.dig('crafting', 'crafts', 0, 'status')).to eq('done')
    end

    it 'cancelar apaga a criação' do
      delete "#{base}/crafts/#{craft_id}", headers: headers
      expect(corpo.dig('crafting', 'crafts')).to eq([])
    end

    it 'criação concluída não aceita mais dias' do
      post "#{base}/crafts/#{craft_id}/complete", params: { force: true }.to_json, headers: headers
      patch "#{base}/crafts/#{craft_id}", params: { craft: { days_worked: 1 } }.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
