# frozen_string_literal: true

require 'rails_helper'

# Fase 2.0 — validators lenientes das camadas do Map Builder + caps de
# tamanho (protege JSONB/broadcast) + map_kind + duplicação preserva camadas.
RSpec.describe BattleMap, 'builder layers (Fase 2.0)', type: :model do
  let(:user) { create(:user) }

  it 'aceita camadas bem-formadas' do
    m = build(:battle_map, user: user,
              map_kind: 'world',
              layers: [{ 'id' => 'L1', 'type' => 'stamps' }],
              terrain_layers: [{ 'id' => 'T1', 'strokes' => [] }],
              stamps: [{ 'id' => 's1', 'assetId' => 'rock', 'x' => 1, 'y' => 2 }],
              paths: [{ 'id' => 'p1', 'kind' => 'river', 'points' => [] }],
              map_effects: { 'vignette' => 0.2 })
    expect(m).to be_valid, -> { m.errors.full_messages.to_s }
  end

  it 'mapa legado (todas as colunas no default) é válido' do
    expect(build(:battle_map, user: user)).to be_valid
  end

  it 'rejeita map_kind fora de battle/world' do
    expect(build(:battle_map, user: user, map_kind: 'nope')).not_to be_valid
  end

  it 'rejeita stamp sem assetId (leniente mas exige id/assetId/x/y)' do
    m = build(:battle_map, user: user, stamps: [{ 'id' => 'x', 'x' => 1, 'y' => 2 }])
    expect(m).not_to be_valid
    expect(m.errors[:stamps]).to be_present
  end

  it 'rejeita terrain_layers/layers/paths que não são array' do
    expect(build(:battle_map, user: user, layers: 'lixo')).not_to be_valid
    expect(build(:battle_map, user: user, terrain_layers: {})).not_to be_valid
    expect(build(:battle_map, user: user, paths: 'x')).not_to be_valid
  end

  it 'rejeita map_effects que não é objeto' do
    expect(build(:battle_map, user: user, map_effects: [1, 2])).not_to be_valid
  end

  it 'aplica cap de stamps (MAX_STAMPS)' do
    too_many = Array.new(BattleMap::MAX_STAMPS + 1) do |i|
      { 'id' => "s#{i}", 'assetId' => 'a', 'x' => 0, 'y' => 0 }
    end
    m = build(:battle_map, user: user, stamps: too_many)
    expect(m).not_to be_valid
    expect(m.errors[:stamps]).to be_present
  end

  it 'aplica cap de strokes por terrain layer (MAX_STROKES_PER_LAYER)' do
    strokes = Array.new(BattleMap::MAX_STROKES_PER_LAYER + 1) { { 'id' => 'k', 'points' => [] } }
    m = build(:battle_map, user: user, terrain_layers: [{ 'id' => 'T', 'strokes' => strokes }])
    expect(m).not_to be_valid
  end

  it 'duplicate_for_user copia as camadas do builder sem refs compartilhadas' do
    src = create(:battle_map, user: user,
                 stamps: [{ 'id' => 's1', 'assetId' => 'rock', 'x' => 1, 'y' => 2 }],
                 terrain_layers: [{ 'id' => 'T1', 'strokes' => [] }])
    other = create(:user)
    copy = described_class.duplicate_for_user(src, other)

    expect(copy.stamps).to eq(src.stamps)
    expect(copy.terrain_layers).to eq(src.terrain_layers)
    copy.stamps.first['x'] = 999
    expect(src.stamps.first['x']).to eq(1) # cópia independente
  end
end
