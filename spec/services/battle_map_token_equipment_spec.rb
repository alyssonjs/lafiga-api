# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BattleMapTokenEquipment, type: :service do
  let(:character) { create(:character) }
  let(:sheet) { create(:sheet, character: character) }
  let(:map) do
    create(
      :battle_map,
      tokens: [{
        'id' => 'hero', 'characterId' => character.id.to_s, 'name' => 'Heroi',
        'color' => '#fff', 'x' => 4, 'y' => 5, 'size' => 1,
        'chibiEquipment' => [{ 'id' => 'stale', 'name' => 'Espada antiga', 'slot' => 'main_hand' }],
      }],
    )
  end

  it 'rebuilds all hand slots from persisted inventory and preserves token position' do
    SheetItem.create!(
      sheet: sheet, item_name: 'Machadinha', category: 'Armas', quantity: 1,
      equipped: true, slot: 'main_hand', props_json: {},
    )
    shield = SheetItem.create!(
      sheet: sheet, item_name: 'Escudo', category: 'Escudos', quantity: 1,
      equipped: false, props_json: {},
    )
    shield.update_columns(equipped: true, slot: 'shield')

    result = described_class.sync!(map: map, character: character)

    token = map.reload.tokens.first
    expect(token).to include('x' => 4, 'y' => 5)
    expect(token['chibiEquipment'].map { |item| item['name'] }).to contain_exactly('Machadinha', 'Escudo')
    expect(result.first[:chibi_equipment]).to eq(token['chibiEquipment'])
  end

  it 'carries the versatile grip in three states (two hands, one hand, never chosen)' do
    SheetItem.create!(
      sheet: sheet, item_name: 'Espada Longa', category: 'Armas', quantity: 1,
      equipped: true, slot: 'main_hand', props_json: { 'using_two_hands' => true },
    )
    # fora das regras de exclusividade de slot (a versátil em duas mãos derrubaria a outra mão): só a foto importa
    lanca = SheetItem.create!(
      sheet: sheet, item_name: 'Lança', category: 'Armas', quantity: 1,
      equipped: false, props_json: { 'using_two_hands' => false },
    )
    lanca.update_columns(equipped: true, slot: 'off_hand')
    SheetItem.create!(
      sheet: sheet, item_name: 'Botas', category: 'Armaduras', quantity: 1,
      equipped: true, slot: 'boots', props_json: {},
    )

    snapshot = described_class.snapshot_for(character).index_by { |item| item['name'] }

    expect(snapshot['Espada Longa']['usingTwoHands']).to be(true)
    expect(snapshot['Lança']['usingTwoHands']).to be(false)
    expect(snapshot['Botas']).not_to have_key('usingTwoHands')
  end

  it 'persists an explicit empty snapshot so clients do not revive stale weapons' do
    result = described_class.sync!(map: map, character: character)

    expect(result.first[:chibi_equipment]).to eq([])
    expect(map.reload.tokens.first).to include('chibiEquipment' => [])
  end

  it 'is idempotent after the canonical snapshot is stored' do
    described_class.sync!(map: map, character: character)

    expect(described_class.sync!(map: map, character: character)).to eq([])
  end

  it 'updates every map token linked to the character' do
    map.update!(tokens: map.tokens + [{
      'id' => 'hero-copy', 'characterId' => character.id.to_s, 'name' => 'Heroi',
      'color' => '#fff', 'x' => 8, 'y' => 9, 'size' => 1,
      'chibiEquipment' => [{ 'id' => 'other-stale', 'name' => 'Arco antigo', 'slot' => 'main_hand' }],
    }])

    changes = described_class.sync!(map: map, character: character)

    expect(changes.pluck(:token_id)).to contain_exactly('hero', 'hero-copy')
    expect(map.reload.tokens.map { |token| token['chibiEquipment'] }).to all(eq([]))
  end
end
