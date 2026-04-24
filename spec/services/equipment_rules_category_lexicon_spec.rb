# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EquipmentRules, type: :service do
  describe '.sheet_item_weapon_category?' do
    it 'accepts English weapon substring' do
      expect(described_class.sheet_item_weapon_category?('weapon')).to be true
    end

    it 'accepts Portuguese bag UI labels' do
      expect(described_class.sheet_item_weapon_category?('Armas')).to be true
      expect(described_class.sheet_item_weapon_category?('arma')).to be true
    end

    it 'does not treat armadura as weapon' do
      expect(described_class.sheet_item_weapon_category?('Armaduras & Escudos')).to be false
    end
  end

  describe '.magic_item_shield_category?' do
    it 'accepts shield and escudo' do
      expect(described_class.magic_item_shield_category?('shield')).to be true
      expect(described_class.magic_item_shield_category?('Escudo')).to be true
    end
  end

  describe '.is_weapon?' do
    it 'treats Armas as weapon when index is not in WEAPON_TABLE' do
      item = Struct.new(:item_index, :item_name, :category).new('slug-sob-encomenda', 'Lâmina', 'Armas')
      expect(described_class.is_weapon?(item)).to be true
    end
  end
end
