# frozen_string_literal: true

require 'rails_helper'

# O que a oficina mostra. ⚠️ "Disponível" desconta o que já está COMPROMETIDO
# com criações em andamento — os materiais só saem ao concluir, e sem isto duas
# criações contariam o mesmo frasco.
RSpec.describe Crafting::Presenter do
  let(:sheet) { create(:sheet, character: create(:character, user: create(:user))) }
  let(:pocao) { oficina_item('alq-pocao-cura', 'Poção de Cura', kind: 'consumable', category: 'potion') }
  let(:extrato) { oficina_item('mat-extrato', 'Extrato Vegetal', props: { 'unit' => 'ml' }) }
  let(:receita) { oficina_receita(produto: pocao, ingredientes: [[extrato, 30, 'ml']], days: 1.5) }

  before { sheet.sheet_known_recipes.create!(crafting_recipe: receita) }

  subject(:estado) { described_class.call(sheet.reload) }

  it 'mostra a receita conhecida com o que o personagem tem e ONDE', :aggregate_failures do
    na_bolsa(sheet, extrato, 40)
    na_bolsa(sheet, extrato, 50, props: { 'cart_id' => 3 })

    r = estado[:recipes].first
    expect(r).to include(id: receita.id, craft: 'alchemy', dc: 12, days: 1.5, max_craftable: 3, ready: true)
    expect(r[:product]).to include(name: 'Poção de Cura', category: 'potion')
    expect(r[:ingredients].first).to include(name: 'Extrato Vegetal', quantity: 30.0, unit: 'ml', item_unit: 'ml',
                                             have: 90, committed: 0, available: 90)
    expect(r[:ingredients].first[:where]).to contain_exactly({ lugar: 'Inventário', quantity: 40 },
                                                             { lugar: 'Carroça do grupo', quantity: 50 })
  end

  it 'receita que o Mestre NÃO ensinou não aparece' do
    outra = oficina_receita(produto: oficina_item('alq-antidoto', 'Antídoto', kind: 'consumable'), ingredientes: [])
    expect(estado[:recipes].map { |r| r[:id] }).not_to include(outra.id)
  end

  it '⚠️ criação em andamento COMPROMETE o material — a segunda vê a falta', :aggregate_failures do
    na_bolsa(sheet, extrato, 45)
    antiga = sheet.sheet_crafts.create!(crafting_recipe: receita, product_name: 'Poção de Cura', quantity: 1,
                                        days_required: 1.5, created_at: 2.days.ago)
    nova = sheet.sheet_crafts.create!(crafting_recipe: receita, product_name: 'Poção de Cura', quantity: 1,
                                      days_required: 1.5)

    ing = estado[:recipes].first[:ingredients].first
    expect(ing).to include(have: 45, committed: 60, available: -15)
    expect(estado[:recipes].first).to include(max_craftable: 0, ready: false)

    # A que começou PRIMEIRO fica com o material; a seguinte vê o que sobra.
    por_id = estado[:crafts].index_by { |c| c[:id] }
    expect(por_id[antiga.id][:materials].first).to include(need: 30, available: 45, missing: 0)
    expect(por_id[nova.id][:materials].first).to include(need: 30, available: 15, missing: 15)
    expect([por_id[antiga.id][:materials_ok], por_id[nova.id][:materials_ok]]).to eq([true, false])
  end

  it 'em andamento vem antes das concluídas' do
    na_bolsa(sheet, extrato, 30)
    feita = sheet.sheet_crafts.create!(crafting_recipe: receita, product_name: 'Poção de Cura', quantity: 1,
                                       days_required: 1, days_worked: 1)
    Crafting::Complete.call(craft: feita)
    andamento = sheet.sheet_crafts.create!(crafting_recipe: receita, product_name: 'Poção de Cura', quantity: 1,
                                           days_required: 1)

    expect(estado[:crafts].map { |c| c[:id] }).to eq([andamento.id, feita.id])
    expect(estado[:crafts].last).to include(status: 'done', materials: [], materials_ok: true)
    expect(estado[:crafts].last[:consumed].first).to include('name' => 'Extrato Vegetal', 'quantity' => 30)
  end
end
