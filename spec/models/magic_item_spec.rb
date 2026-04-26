# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MagicItem, type: :model do
  describe 'normalização e tag' do
    it 'persiste raridade e categoria canónicas, mapeia wondrous legado para gear + is_wondrous e inclui tag magico' do
      mi = described_class.create!(
        slug: "test-mi-#{SecureRandom.hex(4)}",
        name: 'Item Teste',
        rarity: 'very rare',
        category: 'wondrous-item',
        requires_attunement: false,
        effects: [],
      )
      mi.reload
      expect(mi.rarity).to eq('very-rare')
      expect(mi.category).to eq('gear')
      expect(mi.is_wondrous).to be true
      expect(mi.tags).to include('magico')
    end

    it 'inclui is_magical no JSON' do
      mi = described_class.create!(
        slug: "test-mi-json-#{SecureRandom.hex(4)}",
        name: 'Json',
        rarity: 'common',
        category: 'weapon',
        requires_attunement: false,
        effects: [],
      )
      j = mi.as_json
      expect(j['is_magical']).to be true
      expect(j['tags']).to include('magico')
    end

    it 'rejeita raridade inválida' do
      mi = described_class.new(
        slug: "bad-#{SecureRandom.hex(4)}",
        name: 'Bad',
        rarity: 'not-a-rarity',
        category: 'weapon',
        requires_attunement: false,
        effects: [],
      )
      expect(mi).not_to be_valid
      expect(mi.errors[:rarity]).to be_present
    end
  end
end
