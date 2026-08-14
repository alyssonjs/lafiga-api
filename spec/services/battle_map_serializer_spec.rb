# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BattleMapSerializer, type: :service do
  it 'serves canonical sheet customization for a legacy token without mutating the map' do
    character = create(:character)
    create(
      :sheet,
      character: character,
      avatar_customization: { 'outfitId' => 'berserker', 'hairStyle' => 'long' },
    )
    map = create(
      :battle_map,
      tokens: [
        {
          'id' => 'thralliant', 'characterId' => character.id.to_s,
          'name' => 'Thralliant', 'color' => '#fff', 'x' => 1, 'y' => 2, 'size' => 1,
          'chibiCustomization' => { 'outfitId' => 'default', 'hairStyle' => 'short' },
        },
      ],
    )

    payload = described_class.serialize(map, mode: :full)

    expect(payload[:tokens].first['chibiCustomization']).to include(
      'outfitId' => 'berserker', 'hairStyle' => 'long',
    )
    expect(map.reload.tokens.first['chibiCustomization']).to include(
      'outfitId' => 'default', 'hairStyle' => 'short',
    )
  end

  it 'serves canonical persisted hand equipment instead of a stale token snapshot' do
    character = create(:character)
    sheet = create(:sheet, character: character)
    sword = SheetItem.create!(
      sheet: sheet, item_name: 'Espada antiga', category: 'Armas', quantity: 1,
      equipped: true, slot: 'main_hand', props_json: {},
    )
    axe = SheetItem.create!(
      sheet: sheet, item_name: 'Machadinha', category: 'Armas', quantity: 1,
      equipped: true, slot: 'main_hand', props_json: {},
    )
    expect(sword.reload).not_to be_equipped
    map = create(
      :battle_map,
      tokens: [{
        'id' => 'hero', 'characterId' => character.id.to_s, 'name' => 'Heroi',
        'color' => '#fff', 'x' => 1, 'y' => 2, 'size' => 1,
        'chibiEquipment' => [{ 'id' => sword.id.to_s, 'name' => sword.item_name }],
      }],
    )

    payload = described_class.serialize(map, mode: :full)

    expect(payload[:tokens].first['chibiEquipment']).to contain_exactly(
      a_hash_including('id' => axe.id.to_s, 'name' => 'Machadinha', 'slot' => 'main_hand'),
    )
    expect(map.reload.tokens.first['chibiEquipment']).to contain_exactly(
      a_hash_including('id' => sword.id.to_s),
    )
  end
end
