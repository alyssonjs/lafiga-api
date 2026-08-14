# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BattleMapTokenMutations, type: :service do
  let(:map) do
    create(:battle_map, tokens: [
      {
        'id' => 'hero', 'name' => 'Heroi', 'color' => '#fff',
        'x' => 1, 'y' => 2, 'size' => 1,
        'chibiEquipment' => [{ 'id' => 'sword', 'name' => 'Espada' }],
      },
      { 'id' => 'old', 'name' => 'Antigo', 'color' => '#000', 'x' => 0, 'y' => 0, 'size' => 1 },
    ])
  end

  it 'patches only addressed fields and preserves concurrent token data' do
    result = described_class.call(
      map: map,
      mutation: {
        patches: [{ token_id: 'hero', changes: { y: 8 }, unset: [] }],
      },
    )

    hero = map.reload.tokens.find { |token| token['id'] == 'hero' }
    expect(hero).to include('x' => 1, 'y' => 8)
    expect(hero['chibiEquipment']).to eq([{ 'id' => 'sword', 'name' => 'Espada' }])
    expect(result.mutation[:patches]).to eq([
      { token_id: 'hero', changes: { 'y' => 8 }, unset: [] },
    ])
  end

  it 'adds, removes and unsets tokens atomically' do
    described_class.call(
      map: map,
      mutation: {
        additions: [{ id: 'new', name: 'Novo', color: '#123', x: 3, y: 3, size: 1 }],
        patches: [{ token_id: 'hero', changes: {}, unset: ['chibiEquipment'] }],
        delete_ids: ['old'],
      },
    )

    tokens = map.reload.tokens
    expect(tokens.map { |token| token['id'] }).to contain_exactly('hero', 'new')
    expect(tokens.find { |token| token['id'] == 'hero' }).not_to have_key('chibiEquipment')
  end

  it 'treats a retried addition as a no-op instead of replacing the token' do
    described_class.call(
      map: map,
      mutation: {
        additions: [{ id: 'hero', name: 'Snapshot velho', color: '#f00', x: 99, y: 99, size: 1 }],
      },
    )

    expect(map.reload.tokens.find { |token| token['id'] == 'hero' }).to include(
      'name' => 'Heroi', 'x' => 1, 'y' => 2,
    )
  end

  it 'ignores stale visual snapshots for a character-linked token' do
    map.update!(tokens: map.tokens.map do |token|
      token['id'] == 'hero' ? token.merge('characterId' => '42') : token
    end)

    result = described_class.call(
      map: map,
      mutation: {
        patches: [{
          token_id: 'hero',
          changes: {
            x: 9,
            chibiEquipment: [{ id: 'old-axe', name: 'Machado antigo' }],
            chibiCustomization: { outfitId: 'stale' },
          },
          unset: ['chibiEquipment'],
        }],
      },
    )

    hero = map.reload.tokens.find { |token| token['id'] == 'hero' }
    expect(hero).to include('x' => 9)
    expect(hero['chibiEquipment']).to eq([{ 'id' => 'sword', 'name' => 'Espada' }])
    expect(hero).not_to have_key('chibiCustomization')
    expect(result.mutation[:patches]).to eq([
      { token_id: 'hero', changes: { 'x' => 9 }, unset: [] },
    ])
  end

  it 'allows the trusted customization synchronizer to update character visuals' do
    map.update!(tokens: map.tokens.map do |token|
      token['id'] == 'hero' ? token.merge('characterId' => '42') : token
    end)

    described_class.call(
      map: map,
      allow_character_visuals: true,
      mutation: {
        patches: [{
          token_id: 'hero',
          changes: { chibiCustomization: { outfitId: 'berserker' } },
        }],
      },
    )

    expect(map.reload.tokens.find { |token| token['id'] == 'hero' }).to include(
      'chibiCustomization' => { 'outfitId' => 'berserker' },
    )
  end
end
