# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SheetItems::AllocateAmmunitionService do
  let(:user) { create(:user) }
  let(:race) { create(:race) }
  let(:sub_race) { create(:sub_race, race: race) }
  let(:character) { create(:character, user: user, name: 'Quiver Spec PC') }
  let!(:sheet) { create(:sheet, character: character, race: race, sub_race: sub_race) }
  let!(:first_quiver) do
    SheetItem.create!(sheet: sheet, item_name: 'Aljava', item_index: 'aljava', category: 'gear', quantity: 1, source: 'test')
  end
  let!(:second_quiver) do
    SheetItem.create!(sheet: sheet, item_name: 'Aljava reserva', item_index: 'aljava-reserva', category: 'gear', quantity: 1, source: 'test')
  end
  let!(:bolts) do
    SheetItem.create!(sheet: sheet, item_name: 'Virote de Besta', item_index: 'virote', category: 'Armas', quantity: 13, source: 'test')
  end

  it 'moves an entire loose ammunition stack into an unequipped quiver' do
    described_class.new(ammunition: bolts, quiver_id: first_quiver.id, quantity: 13).call

    expect(bolts.reload.quantity).to eq(13)
    expect(bolts.ammunition_container_id).to eq(first_quiver.id.to_s)
    expect(first_quiver.reload).not_to be_equipped
  end

  it 'splits a stack when allocating only part of its ammunition' do
    described_class.new(ammunition: bolts, quiver_id: first_quiver.id, quantity: 5).call

    expect(bolts.reload.quantity).to eq(8)
    contained = sheet.sheet_items.find_by("props_json ->> 'quiver_sheet_item_id' = ?", first_quiver.id.to_s)
    expect(contained.quantity).to eq(5)
    expect(contained.item_index).to eq('virote')
  end

  it 'merges ammunition moved between owned quivers into a matching stack' do
    first_stack = SheetItem.create!(
      sheet: sheet, item_name: 'Flechas', item_index: 'flecha', category: 'Armas', quantity: 4,
      source: 'test', props_json: { SheetItem::AMMUNITION_CONTAINER_PROP => first_quiver.id }
    )
    second_stack = SheetItem.create!(
      sheet: sheet, item_name: 'Flechas', item_index: 'flecha', category: 'Armas', quantity: 7,
      source: 'test', props_json: { SheetItem::AMMUNITION_CONTAINER_PROP => second_quiver.id }
    )

    described_class.new(ammunition: first_stack, quiver_id: second_quiver.id, quantity: 4).call

    expect { first_stack.reload }.to raise_error(ActiveRecord::RecordNotFound)
    expect(second_stack.reload.quantity).to eq(11)
  end

  it 'rejects a quiver from another sheet' do
    other_character = create(:character, user: user, name: 'Other PC')
    other_sheet = create(:sheet, character: other_character, race: race, sub_race: sub_race)
    other_quiver = SheetItem.create!(sheet: other_sheet, item_name: 'Aljava', item_index: 'aljava', quantity: 1, source: 'test')

    expect do
      described_class.new(ammunition: bolts, quiver_id: other_quiver.id, quantity: 1).call
    end.to raise_error(described_class::InvalidAllocation, /não pertence/)
  end

  it 'releases ammunition into the bag when its quiver is removed' do
    described_class.new(ammunition: bolts, quiver_id: first_quiver.id, quantity: 13).call

    first_quiver.destroy!

    expect(bolts.reload.ammunition_container_id).to be_nil
    expect(bolts.quantity).to eq(13)
  end
end
