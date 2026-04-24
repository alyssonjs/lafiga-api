# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'EquipmentRules.weapon_props (DB-first Item)', :aggregate_failures do
  let(:sheet) { create(:sheet) }

  describe 'A1 — Item associado vence WEAPON_TABLE (paridade adaga)' do
    let!(:db_adaga) do
      Item.find_or_initialize_by(api_index: 'adaga').tap do |i|
        i.assign_attributes(
          name: 'Adaga',
          kind: :weapon,
          category: 'simple',
          weight_kg: 0.5,
          value_gp: 2.0,
          props: {
            'type' => 'melee',
            'hands' => 1,
            'damage_die' => '1d4',
            'category' => 'simple',
            'properties' => %w[finesse light thrown],
            'range' => '20/60',
            'cost_cp' => 200,
            'weight_kg' => 0.5
          }
        )
        i.save!
      end
    end

    let(:sheet_item) do
      SheetItem.create!(
        sheet: sheet,
        item_name: 'Adaga',
        item_index: 'adaga',
        item_id: db_adaga.id,
        category: 'Armas',
        quantity: 1,
        equipped: false,
        props_json: {}
      )
    end

    it 'A1.1 — devolve o mesmo shape que WEAPON_TABLE para campos mecânicos' do
      expected = EquipmentRules::WEAPON_TABLE['adaga']
      got = EquipmentRules.weapon_props(sheet_item)
      expect(got).to be_a(Hash)
      %i[type hands light finesse thrown versatile heavy reach loading special category damage_die range cost_cp weight_kg].each do |k|
        next unless expected.key?(k)

        expect(got[k]).to eq(expected[k]), "mismatch on #{k}: got #{got[k].inspect}, expected #{expected[k].inspect}"
      end
    end
  end

  describe 'A2 — arma só na BD (fora de WEAPON_TABLE)' do
    let!(:custom) do
      Item.create!(
        api_index: 'spec-homebrew-hook',
        name: 'Gancho Caseiro',
        kind: :weapon,
        category: 'martial',
        props: {
          'type' => 'melee',
          'hands' => 1,
          'damage_die' => '1d6',
          'category' => 'martial',
          'properties' => %w[light],
          'cost_cp' => 50,
          'weight_kg' => 1.2
        }
      )
    end

    let(:sheet_item) do
      SheetItem.create!(
        sheet: sheet,
        item_name: 'Gancho Caseiro',
        item_index: 'spec-homebrew-hook',
        item_id: custom.id,
        category: 'Armas',
        quantity: 1,
        equipped: false
      )
    end

    it 'A2.1 — resolve via Item mesmo sem linha em WEAPON_TABLE' do
      expect(EquipmentRules::WEAPON_TABLE).not_to have_key('spec-homebrew-hook')
      got = EquipmentRules.weapon_props(sheet_item)
      expect(got[:damage_die]).to eq('1d6')
      expect(got[:light]).to be(true)
      expect(got[:category]).to eq('martial')
    end
  end

  describe 'A3 — fallback WEAPON_TABLE quando não há Item' do
    it 'A3.1 — usa hash legado para chave só em WEAPON_TABLE' do
      fake = OpenStruct.new(item_index: 'club', item_name: 'Porrete', category: 'Armas')
      # Sem registo Item para `club` — ou removemos temporariamente
      Item.where(api_index: 'club').delete_all
      got = EquipmentRules.weapon_props(fake)
      expect(got).to eq(EquipmentRules::WEAPON_TABLE['club'])
    end
  end

  describe 'A4 — props_json quando sem Item nem WEAPON_TABLE' do
    it 'A4.1 — monta a partir de props_json (sem persistir — evita ItemResolver)' do
      si = SheetItem.new(
        sheet: sheet,
        item_name: 'Arma estranha',
        item_index: 'no-table-index-xyz',
        category: 'Armas',
        quantity: 1,
        equipped: false,
        props_json: {
          'type' => 'melee',
          'hands' => 2,
          'heavy' => true,
          'damage_die' => '1d12',
          'category' => 'martial'
        }
      )
      got = EquipmentRules.weapon_props(si)
      expect(got[:hands]).to eq(2)
      expect(got[:heavy]).to be(true)
      expect(got[:damage_die]).to eq('1d12')
    end
  end
end
