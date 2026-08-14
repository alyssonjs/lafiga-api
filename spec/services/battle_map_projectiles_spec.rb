# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BattleMapProjectiles do
  let(:player) { create(:user) }
  let(:dm) { create(:user, role: create(:role, name: 'DM')) }
  let(:character) { create(:character, user: player) }
  let(:sheet) { create(:sheet, character: character) }
  let(:map) do
    create(
      :battle_map,
      user: player,
      width: 8,
      height: 8,
      cells: Array.new(8) { Array.new(8, 'empty') },
      tokens: [
        { 'id' => 'attacker', 'characterId' => character.id.to_s, 'x' => 1, 'y' => 1, 'size' => 1 },
        { 'id' => 'target', 'x' => 5, 'y' => 5, 'size' => 1 }
      ]
    )
  end

  before do
    allow(MapRealtime::Broadcaster).to receive(:token_equipment_changed)
    allow(MapRealtime::Broadcaster).to receive(:dropped_projectiles_changed)
    allow(MapRealtime::Broadcaster).to receive(:projectile_resolved)
  end

  def launch_params(source, kind: 'thrown_weapon')
    {
      projectile_id: 'projectile-1',
      roll_group_id: 'roll-1',
      kind: kind,
      source_item_id: source.id,
      attacker_token_id: 'attacker',
      target_token_id: 'target'
    }
  end

  it 'retira uma arma arremessada da mao e persiste a queda adjacente ao alvo' do
    source = SheetItem.create!(
      sheet: sheet,
      item_index: 'handaxe',
      item_name: 'Machadinha',
      category: 'Armas',
      quantity: 2,
      equipped: true,
      slot: 'main_hand',
      props_json: {}
    )
    tokens = map.tokens.map(&:deep_dup)
    tokens.first['chibiEquipment'] = [{
      'id' => source.id.to_s,
      'refId' => source.item_index,
      'name' => source.item_name,
      'quantity' => 2,
      'equipped' => true,
      'slot' => 'main_hand'
    }]
    map.update!(tokens: tokens)

    projectile = described_class.launch!(map: map, user: player, params: launch_params(source))

    source.reload
    expect(source.quantity).to eq(1)
    expect(source).not_to be_equipped
    expect(source.slot).to be_nil
    expect(projectile).to include(
      'id' => 'projectile-1',
      'kind' => 'thrown_weapon',
      'state' => 'pending',
      'attackerTokenId' => 'attacker',
      'targetTokenId' => 'target'
    )
    expect(projectile.dig('item', 'itemName')).to eq('Machadinha')
    expect((projectile.dig('landing', 'col') - 5).abs).to be <= 1
    expect((projectile.dig('landing', 'row') - 5).abs).to be <= 1
    expect(projectile['landing']).not_to eq('col' => 5, 'row' => 5)
    expect(map.reload.dropped_projectiles).to contain_exactly(projectile)
    expect(map.tokens.first['chibiEquipment']).to eq([])
    expect(MapRealtime::Broadcaster).to have_received(:token_equipment_changed)
      .with(map, 'attacker', [], actor: player)
  end

  it 'consome a ultima flecha e a devolve ao inventario quando um personagem adjacente a recolhe' do
    source = SheetItem.create!(
      sheet: sheet,
      item_index: 'arrow',
      item_name: 'Flecha',
      category: 'Munição',
      quantity: 1,
      equipped: false,
      props_json: {}
    )
    projectile = described_class.launch!(
      map: map,
      user: player,
      params: launch_params(source, kind: 'arrow')
    )
    expect(SheetItem.exists?(source.id)).to be(false)

    described_class.resolve!(map: map, user: dm, projectile_id: projectile['id'], outcome: 'miss')
    landing = map.reload.dropped_projectiles.first.fetch('landing')
    tokens = map.tokens.map(&:deep_dup)
    tokens.first['x'] = landing['col'] - 1
    tokens.first['y'] = landing['row']
    map.update!(tokens: tokens)

    picked = described_class.pick_up!(
      map: map,
      user: player,
      projectile_id: projectile['id'],
      character_id: character.id,
      token_id: 'attacker',
      equip: false
    )

    expect(picked.item_name).to eq('Flecha')
    expect(picked.quantity).to eq(1)
    expect(picked).not_to be_equipped
    expect(map.reload.dropped_projectiles).to be_empty
  end

  it 'permite ao dono do atacante resolver um acerto ao rolar o dano' do
    source = SheetItem.create!(
      sheet: sheet,
      item_index: 'javelin',
      item_name: 'Azagaia',
      category: 'Armas',
      quantity: 1,
      equipped: true,
      slot: 'main_hand',
      props_json: {}
    )
    projectile = described_class.launch!(map: map, user: player, params: launch_params(source))

    resolved = described_class.resolve!(
      map: map,
      user: player,
      projectile_id: projectile['id'],
      outcome: 'hit'
    )

    expect(resolved).to include('state' => 'landed', 'outcome' => 'hit')
    expect(MapRealtime::Broadcaster).to have_received(:projectile_resolved).with(map, resolved, actor: player)
  end

  it 'resolve flecha por roll_group_id em acerto e transmite o voo uma unica vez' do
    source = SheetItem.create!(
      sheet: sheet,
      item_index: 'arrow',
      item_name: 'Flecha',
      category: 'Municao',
      quantity: 2,
      equipped: false,
      props_json: {}
    )
    described_class.launch!(map: map, user: player, params: launch_params(source, kind: 'arrow'))

    resolved = described_class.resolve!(
      map: map,
      user: dm,
      roll_group_id: 'roll-1',
      outcome: 'hit'
    )
    repeated = described_class.resolve!(
      map: map,
      user: dm,
      roll_group_id: 'roll-1',
      outcome: 'hit'
    )

    expect(resolved).to include('kind' => 'arrow', 'state' => 'landed', 'outcome' => 'hit')
    expect(repeated).to eq(resolved)
    expect(MapRealtime::Broadcaster).to have_received(:projectile_resolved).once
  end

  it 'resolve flecha por roll_group_id no erro e impede inverter o resultado depois' do
    source = SheetItem.create!(
      sheet: sheet,
      item_index: 'arrow',
      item_name: 'Flecha',
      category: 'Municao',
      quantity: 1,
      equipped: false,
      props_json: {}
    )
    described_class.launch!(map: map, user: player, params: launch_params(source, kind: 'arrow'))

    resolved = described_class.resolve!(
      map: map,
      user: dm,
      roll_group_id: 'roll-1',
      outcome: 'miss'
    )

    expect(resolved).to include('kind' => 'arrow', 'state' => 'landed', 'outcome' => 'miss')
    expect {
      described_class.resolve!(map: map, user: dm, roll_group_id: 'roll-1', outcome: 'hit')
    }.to raise_error(BattleMapProjectiles::Invalid, 'Projetil ja resolvido com outro resultado')
  end

  it 'mantem a confirmacao de erro exclusiva do mestre' do
    source = SheetItem.create!(
      sheet: sheet,
      item_index: 'javelin',
      item_name: 'Azagaia',
      category: 'Armas',
      quantity: 1,
      equipped: true,
      slot: 'main_hand',
      props_json: {}
    )
    projectile = described_class.launch!(map: map, user: player, params: launch_params(source))

    expect {
      described_class.resolve!(
        map: map,
        user: player,
        projectile_id: projectile['id'],
        outcome: 'miss'
      )
    }.to raise_error(
      BattleMapProjectiles::Forbidden,
      'Apenas o mestre resolve o erro; o atacante resolve o acerto ao rolar dano'
    )
  end

  it 'permite recolher a arma arremessada diretamente na mao e restaura o snapshot do chibi' do
    source = SheetItem.create!(
      sheet: sheet,
      item_index: 'wp-handaxe',
      item_name: 'Machadinha',
      category: 'Armas',
      quantity: 1,
      equipped: true,
      slot: 'main_hand',
      props_json: {}
    )
    projectile = described_class.launch!(map: map, user: player, params: launch_params(source))
    described_class.resolve!(map: map, user: dm, projectile_id: projectile['id'], outcome: 'hit')
    landing = map.reload.dropped_projectiles.first.fetch('landing')
    tokens = map.tokens.map(&:deep_dup)
    tokens.first['x'] = landing['col'] - 1
    tokens.first['y'] = landing['row']
    map.update!(tokens: tokens)
    previous_weapon = SheetItem.create!(
      sheet: sheet,
      item_index: 'club',
      item_name: 'Clava',
      category: 'Armas',
      quantity: 1,
      equipped: true,
      slot: 'main_hand',
      props_json: {}
    )

    picked = described_class.pick_up!(
      map: map,
      user: player,
      projectile_id: projectile['id'],
      character_id: character.id,
      token_id: 'attacker',
      equip: true
    )

    expect(picked).to be_equipped
    expect(picked.slot).to eq('main_hand')
    expect(previous_weapon.reload).not_to be_equipped
    expect(previous_weapon.slot).to be_nil
    expect(map.reload.dropped_projectiles).to be_empty
    expect(map.tokens.first['chibiEquipment']).to contain_exactly(
      include(
        'id' => picked.id.to_s,
        'refId' => 'wp-handaxe',
        'name' => 'Machadinha',
        'equipped' => true,
        'slot' => 'main_hand'
      )
    )
    expect(MapRealtime::Broadcaster).to have_received(:token_equipment_changed)
      .with(map, 'attacker', map.tokens.first['chibiEquipment'], actor: player)
  end

  it 'impede recolher quando o personagem esta a mais de uma celula do item' do
    source = SheetItem.create!(
      sheet: sheet,
      item_name: 'Machadinha',
      category: 'Armas',
      quantity: 1,
      equipped: true,
      slot: 'main_hand',
      props_json: {}
    )
    projectile = described_class.launch!(map: map, user: player, params: launch_params(source))
    described_class.resolve!(map: map, user: dm, projectile_id: projectile['id'], outcome: 'miss')

    tokens = map.reload.tokens.map(&:deep_dup)
    tokens.first['x'] = 0
    tokens.first['y'] = 0
    map.update!(tokens: tokens)

    expect {
      described_class.pick_up!(
        map: map,
        user: player,
        projectile_id: projectile['id'],
        character_id: character.id,
        token_id: 'attacker',
        equip: false
      )
    }.to raise_error(BattleMapProjectiles::Invalid, 'Personagem precisa estar em uma celula adjacente ao item')

    expect(map.reload.dropped_projectiles.map { |entry| entry['id'] }).to include(projectile['id'])
    expect(character.sheet.sheet_items.where(item_name: 'Machadinha')).to be_empty
  end

  it 'permite recolher em uma celula diagonalmente adjacente ao item' do
    source = SheetItem.create!(
      sheet: sheet,
      item_name: 'Flecha',
      category: 'Municao',
      quantity: 1,
      equipped: false,
      props_json: {}
    )
    projectile = described_class.launch!(
      map: map,
      user: player,
      params: launch_params(source, kind: 'arrow')
    )
    described_class.resolve!(map: map, user: dm, projectile_id: projectile['id'], outcome: 'hit')
    landing = map.reload.dropped_projectiles.first.fetch('landing')
    tokens = map.tokens.map(&:deep_dup)
    tokens.first['x'] = [landing['col'] - 1, 0].max
    tokens.first['y'] = [landing['row'] - 1, 0].max
    map.update!(tokens: tokens)

    picked = described_class.pick_up!(
      map: map,
      user: player,
      projectile_id: projectile['id'],
      character_id: character.id,
      token_id: 'attacker',
      equip: false
    )

    expect(picked.item_name).to eq('Flecha')
    expect(map.reload.dropped_projectiles).to be_empty
  end

  it 'permite recolher estando SOBRE a mesma celula do item (em cima)' do
    source = SheetItem.create!(
      sheet: sheet,
      item_name: 'Azagaia',
      category: 'Armas',
      quantity: 1,
      equipped: true,
      slot: 'main_hand',
      props_json: {}
    )
    projectile = described_class.launch!(map: map, user: player, params: launch_params(source))
    described_class.resolve!(map: map, user: dm, projectile_id: projectile['id'], outcome: 'hit')
    landing = map.reload.dropped_projectiles.first.fetch('landing')
    tokens = map.tokens.map(&:deep_dup)
    tokens.first['x'] = landing['col']
    tokens.first['y'] = landing['row']
    map.update!(tokens: tokens)

    picked = described_class.pick_up!(
      map: map,
      user: player,
      projectile_id: projectile['id'],
      character_id: character.id,
      token_id: 'attacker',
      equip: false
    )

    expect(picked.item_name).to eq('Azagaia')
    expect(map.reload.dropped_projectiles).to be_empty
  end

  it 'impede usar um token diferente do personagem informado' do
    other_character = create(:character, user: player)
    source = SheetItem.create!(
      sheet: sheet,
      item_name: 'Azagaia',
      category: 'Armas',
      quantity: 1,
      equipped: true,
      slot: 'main_hand',
      props_json: {}
    )
    projectile = described_class.launch!(map: map, user: player, params: launch_params(source))
    described_class.resolve!(map: map, user: dm, projectile_id: projectile['id'], outcome: 'hit')
    landing = map.reload.dropped_projectiles.first.fetch('landing')
    tokens = map.tokens.map(&:deep_dup)
    tokens << {
      'id' => 'other-token',
      'characterId' => other_character.id.to_s,
      'x' => landing['col'] - 1,
      'y' => landing['row'],
      'size' => 1
    }
    map.update!(tokens: tokens)

    expect {
      described_class.pick_up!(
        map: map,
        user: player,
        projectile_id: projectile['id'],
        character_id: character.id,
        token_id: 'other-token',
        equip: false
      )
    }.to raise_error(BattleMapProjectiles::Invalid, 'Token coletor nao pertence ao personagem')
  end

  it 'impede outro jogador de lancar ou recolher itens com um personagem que nao controla' do
    intruder = create(:user)
    source = SheetItem.create!(
      sheet: sheet,
      item_name: 'Machadinha',
      category: 'Armas',
      quantity: 1,
      equipped: true,
      slot: 'main_hand',
      props_json: {}
    )

    expect {
      described_class.launch!(map: map, user: intruder, params: launch_params(source))
    }.to raise_error(BattleMapProjectiles::Forbidden)
  end
end
