# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MagicItemCatalog do
  describe '.normalize_rarity' do
    it 'normaliza very rare e very_rare para very-rare' do
      expect(described_class.normalize_rarity('very rare')).to eq('very-rare')
      expect(described_class.normalize_rarity('VERY_RARE')).to eq('very-rare')
    end

    it 'mantém uncommon, rare, etc.' do
      expect(described_class.normalize_rarity('uncommon')).to eq('uncommon')
      expect(described_class.normalize_rarity('rare')).to eq('rare')
    end

    it 'devolve nil para lixo' do
      expect(described_class.normalize_rarity('xyz')).to be_nil
      expect(described_class.normalize_rarity('')).to be_nil
    end
  end

  describe '.normalize_category' do
    it 'normaliza wondrous (legado) para gear' do
      expect(described_class.normalize_category('wondrous-item')).to eq('gear')
      expect(described_class.normalize_category('wondrous item')).to eq('gear')
    end

    it 'mapeia arma e escudo em PT' do
      expect(described_class.normalize_category('Arma')).to eq('weapon')
      expect(described_class.normalize_category('escudo')).to eq('shield')
    end

    it 'aceita veículo, montaria e kit' do
      expect(described_class.normalize_category('vehicle')).to eq('vehicle')
      expect(described_class.normalize_category('mount')).to eq('mount')
      expect(described_class.normalize_category('kit')).to eq('kit')
      expect(described_class.normalize_category('veículo')).to eq('vehicle')
      expect(described_class.normalize_category('montaria')).to eq('mount')
    end

    it 'devolve nil para desconhecido' do
      expect(described_class.normalize_category('totally-invalid')).to be_nil
    end
  end

  describe '.ensure_magico_tag' do
    it 'adiciona magico se faltar' do
      expect(described_class.ensure_magico_tag(%w[foo])).to eq(%w[foo magico])
    end

    it 'não duplica magico' do
      expect(described_class.ensure_magico_tag(%w[magico])).to eq(%w[magico])
    end
  end
end
