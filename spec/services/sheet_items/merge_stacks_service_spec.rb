# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SheetItems::MergeStacksService do
  let(:user) { create(:user) }
  let(:race) { create(:race) }
  let(:sub_race) { create(:sub_race, race: race) }
  let(:character) { create(:character, user: user, name: 'Merge Spec PC') }
  let!(:sheet) { create(:sheet, character: character, race: race, sub_race: sub_race) }

  it 'soma quantidades no destino e destrói a origem' do
    target = SheetItem.create!(sheet: sheet, item_name: 'Virote de Gelo', item_index: 'virote-gelo', category: 'Armas', quantity: 14, source: 'test')
    source = SheetItem.create!(sheet: sheet, item_name: 'Virote de Gelo', item_index: 'virote-gelo', category: 'Armas', quantity: 6, source: 'test')

    result = described_class.new(sheet: sheet, source_id: source.id, target_id: target.id).call

    expect(target.reload.quantity).to eq(20)
    expect { source.reload }.to raise_error(ActiveRecord::RecordNotFound)
    expect(result.map { |i| i[:id] }).to eq([target.id])
  end

  it 'une mesmo quando props/source divergem (mais permissivo que o auto-stack)' do
    # É exatamente o caso que o auto-stack RECUSA: mesmo catálogo, mas um lote
    # carrega quiver_sheet_item_id residual e outra source.
    target = SheetItem.create!(sheet: sheet, item_name: 'Virote de Gelo', item_index: 'virote-gelo', category: 'Armas', quantity: 14, source: 'test')
    source = SheetItem.create!(
      sheet: sheet, item_name: 'Virote de Gelo', item_index: 'virote-gelo', category: 'Armas', quantity: 6,
      source: 'map_pickup', props_json: { SheetItem::AMMUNITION_CONTAINER_PROP => '999' }
    )

    described_class.new(sheet: sheet, source_id: source.id, target_id: target.id).call

    expect(target.reload.quantity).to eq(20)
    expect(target.props_json).to be_blank # destino preserva os próprios props
    expect { source.reload }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'recusa unir itens de catálogos diferentes' do
    target = SheetItem.create!(sheet: sheet, item_name: 'Virote de Gelo', item_index: 'virote-gelo', category: 'Armas', quantity: 14, source: 'test')
    other = SheetItem.create!(sheet: sheet, item_name: 'Flecha', item_index: 'flecha', category: 'Armas', quantity: 6, source: 'test')

    expect { described_class.new(sheet: sheet, source_id: other.id, target_id: target.id).call }
      .to raise_error(SheetItems::MergeStacksService::InvalidMerge, /mesmo tipo/)
    expect(target.reload.quantity).to eq(14)
    expect(other.reload.quantity).to eq(6)
  end

  it 'recusa unir item equipado' do
    target = SheetItem.create!(sheet: sheet, item_name: 'Virote de Gelo', item_index: 'virote-gelo', category: 'Armas', quantity: 14, source: 'test')
    equipped = SheetItem.create!(sheet: sheet, item_name: 'Virote de Gelo', item_index: 'virote-gelo', category: 'Armas', quantity: 6, source: 'test', equipped: true, slot: 'main_hand')

    expect { described_class.new(sheet: sheet, source_id: equipped.id, target_id: target.id).call }
      .to raise_error(SheetItems::MergeStacksService::InvalidMerge, /equipados/)
  end

  it 'recusa unir item com estado por-instância (cargas/sintonização)' do
    target = SheetItem.create!(sheet: sheet, item_name: 'Varinha', item_index: 'varinha', category: 'gear', quantity: 1, source: 'test', props_json: { 'charges' => 7 })
    source = SheetItem.create!(sheet: sheet, item_name: 'Varinha', item_index: 'varinha', category: 'gear', quantity: 1, source: 'test', props_json: { 'charges' => 3 })

    expect { described_class.new(sheet: sheet, source_id: source.id, target_id: target.id).call }
      .to raise_error(SheetItems::MergeStacksService::InvalidMerge, /cargas/)
  end

  it 'recusa origem e destino iguais' do
    target = SheetItem.create!(sheet: sheet, item_name: 'Virote de Gelo', item_index: 'virote-gelo', category: 'Armas', quantity: 14, source: 'test')

    expect { described_class.new(sheet: sheet, source_id: target.id, target_id: target.id).call }
      .to raise_error(SheetItems::MergeStacksService::InvalidMerge, /mesmo item/)
  end

  it 'recusa destino de outra ficha' do
    target = SheetItem.create!(sheet: sheet, item_name: 'Virote de Gelo', item_index: 'virote-gelo', category: 'Armas', quantity: 14, source: 'test')
    other = create(:character, user: user, name: 'Outro PC')
    other_sheet = create(:sheet, character: other, race: race, sub_race: sub_race)
    foreign = SheetItem.create!(sheet: other_sheet, item_name: 'Virote de Gelo', item_index: 'virote-gelo', category: 'Armas', quantity: 6, source: 'test')

    expect { described_class.new(sheet: sheet, source_id: target.id, target_id: foreign.id).call }
      .to raise_error(SheetItems::MergeStacksService::InvalidMerge, /não encontrado/)
  end

  it 'une itens custom pelo nome+categoria quando não há item_index' do
    target = SheetItem.create!(sheet: sheet, item_name: 'Poção da Sorte', item_id: nil, category: 'consumable', quantity: 2, source: 'test')
    source = SheetItem.create!(sheet: sheet, item_name: 'poção da sorte', item_id: nil, category: 'consumable', quantity: 3, source: 'test')

    described_class.new(sheet: sheet, source_id: source.id, target_id: target.id).call
    expect(target.reload.quantity).to eq(5)
  end
end
