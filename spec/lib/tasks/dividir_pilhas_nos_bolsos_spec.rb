# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# A Maleta de Alquimia tinha "Poção de Cura ×4" num bolso só (de antes de o
# bolso levar uma unidade por vez). A rake reparte: uma por bolso livre, o que
# não couber volta para fora — e nunca mexe em flecha nem matéria-prima.
RSpec.describe 'dnd:dividir_pilhas_nos_bolsos' do
  before(:all) do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  let(:sheet) { create(:sheet, character: create(:character, user: create(:user))) }
  let!(:catalogo_pocao) { Item.find_by(api_index: 'pocao-rk') || Item.create!(api_index: 'pocao-rk', name: 'Poção de Cura', kind: 'consumable') }

  def bolsa!(slots)
    Item.create!(api_index: "maleta-rk-#{slots}", name: 'Maleta', kind: 'gear', category: 'bag',
                 props: { 'capacity_kg' => 15, 'bag_slots' => slots })
    SheetItem.create!(sheet: sheet, item_name: 'Maleta', item_index: "maleta-rk-#{slots}", category: 'Itens Gerais',
                      quantity: 1, source: 'test', equipped: true, slot: 'main_hand')
  end

  def pendurada!(bolsa, qtd, index: 'pocao-rk', nome: 'Poção de Cura')
    linha = SheetItem.create!(sheet: sheet, item_name: nome, item_index: index, category: 'Poções',
                              quantity: 1, source: 'test')
    # Pilha ANTIGA: gravada direto, como ficou antes da regra.
    linha.update_columns(quantity: qtd, props_json: { SheetItem::BAG_SLOT_CONTAINER_PROP => bolsa.id })
    linha
  end

  def rodar(env = {})
    env.each { |k, v| ENV[k] = v }
    Rake::Task['dnd:dividir_pilhas_nos_bolsos'].reenable
    expect { Rake::Task['dnd:dividir_pilhas_nos_bolsos'].invoke }.to output(/dividir_pilhas_nos_bolsos/).to_stdout
  ensure
    env.each_key { |k| ENV.delete(k) }
  end

  def nos_bolsos(bolsa)
    sheet.sheet_items.reload.select { |si| si.stored_on_bag_slot_id.to_s == bolsa.id.to_s }.map(&:quantity)
  end

  it 'reparte a pilha: uma poção por bolso livre' do
    maleta = bolsa!(16)
    pendurada!(maleta, 4)

    rodar

    expect(nos_bolsos(maleta)).to eq([1, 1, 1, 1])
  end

  it 'sem bolso livre para todas, o resto volta para FORA — fundido na pilha solta' do
    maleta = bolsa!(2)
    pendurada!(maleta, 4)
    solta = SheetItem.create!(sheet: sheet, item_name: 'Poção de Cura', item_index: 'pocao-rk', category: 'Poções',
                              quantity: 3, source: 'test')

    rodar

    expect(nos_bolsos(maleta)).to eq([1, 1])
    expect(solta.reload.quantity).to eq(5)
  end

  it 'DRY_RUN só relata — não grava nada' do
    maleta = bolsa!(16)
    pendurada!(maleta, 4)

    rodar('DRY_RUN' => '1')

    expect(nos_bolsos(maleta)).to eq([4])
  end

  it 'flecha e matéria-prima NÃO se dividem — não são consumível' do
    Item.create!(api_index: 'flecha-rk', name: 'Flecha', kind: 'ammunition')
    maleta = bolsa!(16)
    pendurada!(maleta, 20, index: 'flecha-rk', nome: 'Flecha')

    rodar

    expect(nos_bolsos(maleta)).to eq([20])
  end
end
