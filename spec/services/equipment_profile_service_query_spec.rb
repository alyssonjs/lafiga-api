# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EquipmentProfileService, 'query budget (includes :item)', :aggregate_failures do
  let(:sheet) { create(:sheet) }

  it 'C1.1 — N sheet_items com Item não dispara N+1 SELECT em items' do
    n = 12
    items = n.times.map do |i|
      idx = "spec-weapon-#{i}-#{SecureRandom.hex(4)}"
      Item.create!(
        api_index: idx,
        name: "Arma Spec #{i}",
        kind: :weapon,
        category: 'simple',
        weight_kg: 1.0,
        value_gp: 1.0,
        props: {
          'type' => 'melee',
          'hands' => 1,
          'damage_die' => '1d4',
          'category' => 'simple',
          'properties' => %w[light]
        }
      )
    end

    items.each do |db_item|
      SheetItem.create!(
        sheet: sheet,
        item_name: db_item.name,
        item_index: db_item.api_index,
        item_id: db_item.id,
        category: 'Armas',
        quantity: 1,
        equipped: false,
        props_json: {}
      )
    end

    item_selects = 0
    sub = ActiveSupport::Notifications.subscribe('sql.active_record') do |_n, _s, _f, _id, payload|
      sql = payload[:sql].to_s
      item_selects += 1 if sql.match?(/FROM "items"/i) && sql.match?(/SELECT/i)
    end

    begin
      described_class.new(sheet).call
    ensure
      ActiveSupport::Notifications.unsubscribe(sub)
    end

    expect(item_selects).to be <= 3
  end
end
