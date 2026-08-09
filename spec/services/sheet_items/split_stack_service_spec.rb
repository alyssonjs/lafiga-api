# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SheetItems::SplitStackService do
  let(:user) { create(:user) }
  let(:race) { create(:race) }
  let(:sub_race) { create(:sub_race, race: race) }
  let(:character) { create(:character, user: user, name: 'Split Spec PC') }
  let!(:sheet) { create(:sheet, character: character, race: race, sub_race: sub_race) }

  let!(:stack) do
    SheetItem.create!(sheet: sheet, item_name: 'Virote de Gelo', item_index: 'virote-gelo', category: 'Armas', quantity: 20, source: 'test', notes: 'gelado', position: 5)
  end

  it 'separa N unidades numa nova pilha e reduz a original' do
    result = described_class.new(item: stack, quantity: 5).call

    expect(stack.reload.quantity).to eq(15)
    new_stack = sheet.sheet_items.where.not(id: stack.id).first
    expect(new_stack.quantity).to eq(5)
    expect(new_stack.item_index).to eq('virote-gelo')
    expect(new_stack.notes).to eq('gelado')
    expect(new_stack).not_to be_equipped
    expect(result.map { |i| i[:id] }).to include(stack.id, new_stack.id)
  end

  it 'coloca a nova pilha no fim da bolsa (maior position)' do
    other = SheetItem.create!(sheet: sheet, item_name: 'Corda', item_index: 'corda', category: 'gear', quantity: 1, source: 'test', position: 30)

    described_class.new(item: stack, quantity: 4).call
    new_stack = sheet.sheet_items.where.not(id: [stack.id, other.id]).first

    expect(new_stack.position).to be > other.position
  end

  it 'rejeita separar a pilha inteira (quantity >= total)' do
    expect { described_class.new(item: stack, quantity: 20).call }
      .to raise_error(SheetItems::SplitStackService::InvalidSplit)
    expect(stack.reload.quantity).to eq(20)
  end

  it 'rejeita quantidade zero ou negativa' do
    expect { described_class.new(item: stack, quantity: 0).call }
      .to raise_error(SheetItems::SplitStackService::InvalidSplit)
  end

  it 'rejeita separar item equipado' do
    equipped = SheetItem.create!(sheet: sheet, item_name: 'Espada', item_index: 'espada', category: 'Armas', quantity: 2, source: 'test', equipped: true, slot: 'main_hand')
    expect { described_class.new(item: equipped, quantity: 1).call }
      .to raise_error(SheetItems::SplitStackService::InvalidSplit, /equipado/)
  end

  it 'rejeita separar item com estado por-instância' do
    wand = SheetItem.create!(sheet: sheet, item_name: 'Varinha', item_index: 'varinha', category: 'gear', quantity: 2, source: 'test', props_json: { 'charges' => 7 })
    expect { described_class.new(item: wand, quantity: 1).call }
      .to raise_error(SheetItems::SplitStackService::InvalidSplit, /cargas/)
  end
end
