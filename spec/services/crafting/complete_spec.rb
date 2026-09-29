# frozen_string_literal: true

require 'rails_helper'

# CONCLUIR é o único momento em que o material sai da bolsa (decisão da mesa,
# 29/09). Estes testes cravam DE ONDE sai, o que acontece quando falta, e onde
# o produto cai.
RSpec.describe Crafting::Complete do
  let(:sheet) { create(:sheet, character: create(:character, user: create(:user))) }
  let(:pocao) { oficina_item('alq-pocao-cura', 'Poção de Cura', kind: 'consumable', category: 'potion') }
  let(:extrato) { oficina_item('mat-extrato', 'Extrato Vegetal', props: { 'unit' => 'ml' }) }
  let(:fungo) { oficina_item('mat-fungo', 'Fungo') }
  let(:acido) { oficina_item('mat-acido', 'Componente Ácido') }
  let(:receita) do
    oficina_receita(produto: pocao, ingredientes: [[extrato, 30, 'ml'], [fungo, 2, 'un', 1], [acido, 2, 'un', 1]])
  end

  def criacao(qtd = 1)
    sheet.sheet_crafts.create!(crafting_recipe: receita, product_name: 'Poção de Cura', quantity: qtd,
                               days_required: 2 * qtd, days_worked: 2 * qtd)
  end

  it 'desconta o SOLTO antes da bolsa e a CARROÇA por último', :aggregate_failures do
    bolsa = SheetItem.create!(sheet: sheet, item_name: 'Mochila', quantity: 1, props_json: {})
    na_carroca = na_bolsa(sheet, extrato, 100, props: { 'cart_id' => 7 })
    na_mochila = na_bolsa(sheet, extrato, 20, props: { 'bag_sheet_item_id' => bolsa.id })
    solto = na_bolsa(sheet, extrato, 5)
    na_bolsa(sheet, fungo, 2)

    craft = described_class.call(craft: criacao)

    expect(SheetItem.exists?(solto.id)).to be(false)
    expect(SheetItem.exists?(na_mochila.id)).to be(false)
    expect(na_carroca.reload.quantity).to eq(95)
    expect(craft.consumed.select { |c| c['item_id'] == extrato.id }.map { |c| [c['lugar'], c['quantity']] })
      .to eq([['Inventário', 5], ['Mochila', 20], ['Carroça do grupo', 5]])
  end

  it '⚠️ item EQUIPADO não é matéria-prima — nunca sai', :aggregate_failures do
    equipado = na_bolsa(sheet, extrato, 30, equipped: true)
    na_bolsa(sheet, fungo, 2)

    expect { described_class.call(craft: criacao) }.to raise_error(described_class::MissingMaterials, /30 ml de Extrato/)
    expect(equipado.reload.quantity).to eq(30)
  end

  it 'na alternativa ("Fungo OU Ácido") usa a que o personagem TEM', :aggregate_failures do
    na_bolsa(sheet, extrato, 30)
    acidos = na_bolsa(sheet, acido, 3)

    described_class.call(craft: criacao)

    expect(acidos.reload.quantity).to eq(1)
  end

  it 'multiplica pela quantidade e arredonda para cima o que não é inteiro' do
    na_bolsa(sheet, extrato, 90)
    fungos = na_bolsa(sheet, fungo, 10)

    described_class.call(craft: criacao(3))

    expect(fungos.reload.quantity).to eq(4)
  end

  context 'quando falta material' do
    before do
      na_bolsa(sheet, extrato, 10)
      na_bolsa(sheet, fungo, 2)
    end

    it 'recusa e NÃO mexe em nada', :aggregate_failures do
      craft = criacao
      expect { described_class.call(craft: craft) }
        .to raise_error(described_class::MissingMaterials) { |e| expect(e.missing).to eq([{ name: 'Extrato Vegetal', unit: 'ml', missing: 20 }]) }
      expect(craft.reload.status).to eq('in_progress')
      expect(sheet.sheet_items.where(item_id: extrato.id).sum(:quantity)).to eq(10)
    end

    it 'com `force` conclui gastando o que houver', :aggregate_failures do
      craft = described_class.call(craft: criacao, force: true)
      expect(craft.status).to eq('done')
      expect(sheet.sheet_items.where(item_id: extrato.id)).to be_empty
    end
  end

  describe 'o produto' do
    before do
      na_bolsa(sheet, extrato, 60)
      na_bolsa(sheet, fungo, 4)
    end

    it 'cai na gaveta do catálogo, marcado como criado', :aggregate_failures do
      craft = described_class.call(craft: criacao)
      produto = SheetItem.find(craft.product_sheet_item_id)

      expect(produto).to have_attributes(item_id: pocao.id, item_index: 'alq-pocao-cura', category: 'Poções',
                                         source: 'crafted', quantity: 1, equipped: false)
      expect(craft).to have_attributes(status: 'done', completed_at: be_present)
    end

    it 'SOMA com a poção criada que o personagem já tinha' do
      primeira = described_class.call(craft: criacao)
      segunda = described_class.call(craft: criacao)

      expect(segunda.product_sheet_item_id).to eq(primeira.product_sheet_item_id)
      expect(SheetItem.find(primeira.product_sheet_item_id).quantity).to eq(2)
    end
  end

  it 'não conclui duas vezes' do
    na_bolsa(sheet, extrato, 60)
    na_bolsa(sheet, fungo, 4)
    craft = described_class.call(craft: criacao)

    expect { described_class.call(craft: craft) }.to raise_error(described_class::Invalid, /já foi concluída/)
  end
end
