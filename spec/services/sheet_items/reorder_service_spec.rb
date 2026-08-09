# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SheetItems::ReorderService do
  let(:user) { create(:user) }
  let(:race) { create(:race) }
  let(:sub_race) { create(:sub_race, race: race) }
  let(:character) { create(:character, user: user, name: 'Reorder Spec PC') }
  let!(:sheet) { create(:sheet, character: character, race: race, sub_race: sub_race) }

  let!(:a) { SheetItem.create!(sheet: sheet, item_name: 'Aljava', item_index: 'aljava', category: 'gear', quantity: 1, source: 'test', position: 10) }
  let!(:b) { SheetItem.create!(sheet: sheet, item_name: 'Corda', item_index: 'corda', category: 'gear', quantity: 1, source: 'test', position: 20) }
  let!(:c) { SheetItem.create!(sheet: sheet, item_name: 'Tocha', item_index: 'tocha', category: 'gear', quantity: 1, source: 'test', position: 30) }

  def ordered_names
    sheet.sheet_items.reload.order(:position, :id).pluck(:item_name)
  end

  it 'grava as posições na ordem recebida (1..N)' do
    described_class.new(sheet: sheet, ordered_ids: [c.id, a.id, b.id]).call

    expect(ordered_names).to eq(%w[Tocha Aljava Corda])
    expect([a, b, c].map { |i| i.reload.position }).to eq([2, 3, 1])
  end

  it 'devolve o inventário já ordenado por position' do
    result = described_class.new(sheet: sheet, ordered_ids: [b.id, c.id, a.id]).call

    expect(result.map { |i| i[:name] }).to eq(%w[Corda Tocha Aljava])
    expect(result.map { |i| i[:position] }).to eq([1, 2, 3])
  end

  it 'empurra itens NÃO listados para o fim preservando a ordem relativa' do
    described_class.new(sheet: sheet, ordered_ids: [c.id]).call

    # c vira 1; a e b não citados vão para o fim mantendo ordem atual (a antes de b).
    expect(ordered_names).to eq(%w[Tocha Aljava Corda])
    expect(c.reload.position).to eq(1)
    expect(a.reload.position).to eq(2)
    expect(b.reload.position).to eq(3)
  end

  it 'ignora ids que não pertencem à ficha' do
    other = create(:character, user: user, name: 'Outro PC')
    other_sheet = create(:sheet, character: other, race: race, sub_race: sub_race)
    foreign = SheetItem.create!(sheet: other_sheet, item_name: 'Estranho', item_index: 'x', category: 'gear', quantity: 1, source: 'test')

    described_class.new(sheet: sheet, ordered_ids: [foreign.id, b.id, a.id, c.id]).call

    expect(ordered_names).to eq(%w[Corda Aljava Tocha])
    expect(foreign.reload.sheet_id).to eq(other_sheet.id)
  end

  it 'rejeita lista vazia' do
    expect { described_class.new(sheet: sheet, ordered_ids: []).call }
      .to raise_error(SheetItems::ReorderService::InvalidReorder)
  end

  it 'não dispara efeito colateral em itens equipados (mantém equip/slot)' do
    equipped = SheetItem.create!(sheet: sheet, item_name: 'Espada', item_index: 'espada', category: 'Armas', quantity: 1, source: 'test', equipped: true, slot: 'main_hand', position: 5)

    described_class.new(sheet: sheet, ordered_ids: [b.id, a.id, c.id]).call

    expect(equipped.reload).to be_equipped
    expect(equipped.slot).to eq('main_hand')
  end
end
