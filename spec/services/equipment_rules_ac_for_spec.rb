# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'EquipmentRules.ac_for (Item armor / shield)', :aggregate_failures do
  let(:sheet) { create(:sheet, dex: 14, str: 16) } # +2 DEX mod

  describe 'B1 — armadura só em Item (fora de ARMOR_TABLE)' do
    let!(:homebrew_armor) do
      Item.create!(
        api_index: 'spec-armadura-ritual',
        name: 'Manto Ritual',
        kind: :armor,
        category: 'light',
        props: {
          'ac_base' => 12,
          'dex_cap' => nil,
          'stealth_dis' => false,
          'str_req' => nil
        }
      )
    end

    let(:armor_si) do
      SheetItem.create!(
        sheet: sheet,
        item_name: 'Manto Ritual',
        item_index: 'spec-armadura-ritual',
        item_id: homebrew_armor.id,
        category: 'Armaduras & Escudos',
        quantity: 1,
        equipped: true,
        slot: 'armor'
      )
    end

    it 'B1.1 — usa ac_base + DEX quando não existe linha em ARMOR_TABLE' do
      expect(EquipmentRules::ARMOR_TABLE).not_to have_key('spec-armadura-ritual')
      out = EquipmentRules.ac_for(sheet: sheet, armor_item: armor_si, shield_item: nil)
      expect(out[:ac]).to eq(14) # 12 + 2 DEX
      expect(out[:armor_category]).to eq('light')
      expect(out[:armor_equipped]).to be(true)
    end
  end

  describe 'B2 — paridade com ARMOR_TABLE (leather / couro via Item)' do
    let!(:leather) do
      Item.find_or_initialize_by(api_index: 'leather').tap do |i|
        i.assign_attributes(
          name: 'Couro',
          kind: :armor,
          category: 'light',
          props: {
            'ac_base' => 11,
            'dex_cap' => nil,
            'stealth_dis' => false,
            'str_req' => nil
          }
        )
        i.save!
      end
    end

    let(:armor_si) do
      SheetItem.create!(
        sheet: sheet,
        item_name: 'Couro',
        item_index: 'leather',
        item_id: leather.id,
        category: 'Armaduras & Escudos',
        quantity: 1,
        equipped: true,
        slot: 'armor'
      )
    end

    it 'B2.1 — mesmo CA que a entrada legada da tabela' do
      legacy = EquipmentRules.ac_for(sheet: sheet, armor_item: OpenStruct.new(item_index: 'leather', item_name: 'Leather'), shield_item: nil)
      from_db = EquipmentRules.ac_for(sheet: sheet, armor_item: armor_si, shield_item: nil)
      expect(from_db[:ac]).to eq(legacy[:ac])
      expect(from_db[:stealth_disadvantage]).to eq(legacy[:stealth_disadvantage])
    end
  end
end
