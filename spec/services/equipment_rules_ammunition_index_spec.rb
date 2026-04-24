# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'EquipmentRules.weapon_props — ammunition_index contract (E1)', :aggregate_failures do
  let(:sheet) { create(:sheet) }

  it 'E1.1 — arma com munição inclui ammunition_index vindo de Item.props' do
    idx = "spec-longbow-ammo-#{SecureRandom.hex(4)}"
    db_item = Item.create!(
      api_index: idx,
      name: 'Arco Longo Spec',
      kind: :weapon,
      category: 'martial',
      props: {
        'type' => 'ranged',
        'hands' => 2,
        'damage_die' => '1d8',
        'category' => 'martial',
        'properties' => %w[ammunition heavy two-handed],
        'range' => '150/600',
        'ammunition_index' => 'flecha'
      }
    )

    si = SheetItem.create!(
      sheet: sheet,
      item_name: db_item.name,
      item_index: idx,
      item_id: db_item.id,
      category: 'Armas',
      quantity: 1,
      equipped: true,
      slot: 'main_hand',
      props_json: {}
    )

    got = EquipmentRules.weapon_props(si)
    expect(got[:ammunition]).to eq(true)
    expect(got[:ammunition_index]).to eq('flecha')
  end

  it 'E1.2 — aceita alias ammo_index' do
    idx = "spec-crossbow-ammo-#{SecureRandom.hex(4)}"
    db_item = Item.create!(
      api_index: idx,
      name: 'Besta Leve Spec',
      kind: :weapon,
      category: 'simple',
      props: {
        'type' => 'ranged',
        'hands' => 2,
        'damage_die' => '1d8',
        'category' => 'simple',
        'properties' => %w[ammunition two-handed],
        'range' => '80/320',
        'ammo_index' => 'virote'
      }
    )

    si = SheetItem.create!(
      sheet: sheet,
      item_name: db_item.name,
      item_index: idx,
      item_id: db_item.id,
      category: 'Armas',
      quantity: 1,
      equipped: false,
      props_json: {}
    )

    got = EquipmentRules.weapon_props(si)
    expect(got[:ammunition]).to eq(true)
    expect(got[:ammunition_index]).to eq('virote')
  end
end
