# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BattleMapCharacterCustomization, type: :service do
  let(:user) { create(:user) }
  let(:character) { create(:character, user: user) }
  let!(:sheet) do
    create(
      :sheet,
      character: character,
      avatar_customization: { 'outfitId' => 'berserker', 'hairStyle' => 'long' },
    )
  end
  let!(:map) do
    create(
      :battle_map,
      user: user,
      tokens: [
        {
          'id' => 'thralliant', 'characterId' => character.id.to_s,
          'name' => 'Thralliant', 'color' => '#fff', 'x' => 7, 'y' => 9, 'size' => 1,
          'chibiCustomization' => { 'outfitId' => 'default' },
          'chibiEquipment' => [{ 'name' => 'Machadinha', 'slot' => 'main_hand' }],
        },
      ],
    )
  end

  it 'patches customization and preserves position and equipment' do
    expect {
      expect(described_class.sync!(character: character, actor: user)).to eq([map.id])
    }.to have_broadcasted_to(MapChannel.stream_name(map)).with { |data|
      expect(data['event']).to eq('tokens_patched')
      expect(data.dig('payload', 'patches', 0, 'changes', 'chibiCustomization')).to include(
        'outfitId' => 'berserker', 'hairStyle' => 'long',
      )
    }

    persisted = map.reload.tokens.first
    expect(persisted).to include('x' => 7, 'y' => 9)
    expect(persisted['chibiEquipment']).to eq([{ 'name' => 'Machadinha', 'slot' => 'main_hand' }])
    expect(persisted['chibiCustomization']).to include(
      'outfitId' => 'berserker', 'hairStyle' => 'long',
    )
  end

  it 'is idempotent when the token already has the current customization' do
    described_class.sync!(character: character, actor: user)

    expect {
      expect(described_class.sync!(character: character, actor: user)).to eq([])
    }.not_to have_broadcasted_to(MapChannel.stream_name(map))
  end
end
