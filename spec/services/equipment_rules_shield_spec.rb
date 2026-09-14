# frozen_string_literal: true

require 'rails_helper'

# Escudo do CATÁLOGO na conta da ficha (14/09/2026). O PHB só tem o escudo +2,
# mas o mestre cria os seus — o "Escudo Grande" da mesa dá desvantagem em
# Furtividade.
#
# A linha da ficha fica SEM salvar de propósito: `ac_for` só lê `item`, e a
# validação de proficiência do `SheetItem` não é o assunto aqui.
RSpec.describe 'EquipmentRules.ac_for — escudo do catálogo', :aggregate_failures do
  let(:sheet) { create(:sheet, dex: 14, str: 16) }

  def escudo(idx, props)
    Item.create!(api_index: idx, name: idx.tr('-', ' ').capitalize, kind: :shield, category: 'shield', props: props)
  end

  def na_mao(item)
    SheetItem.new(sheet: sheet, item: item, item_name: item.name, item_index: item.api_index,
                  category: 'Armaduras & Escudos', quantity: 1, equipped: true, slot: 'shield')
  end

  describe 'desvantagem em Furtividade' do
    it 'o escudo que declara a marca impõe a desvantagem, mesmo sem armadura' do
      grande = na_mao(escudo('spec-escudo-grande', 'ac_base' => 3, 'stealth_dis' => true))

      out = EquipmentRules.ac_for(sheet: sheet, armor_item: nil, shield_item: grande)

      expect(out[:stealth_disadvantage]).to be(true)
    end

    it 'escudo sem a marca não impõe nada' do
      comum = na_mao(escudo('spec-escudo-comum', 'ac_base' => 2))

      out = EquipmentRules.ac_for(sheet: sheet, armor_item: nil, shield_item: comum)

      expect(out[:stealth_disadvantage]).to be(false)
    end

    it 'REGRESSÃO: a armadura com a marca continua impondo, com qualquer escudo' do
      comum = na_mao(escudo('spec-escudo-comum', 'ac_base' => 2))
      cota = OpenStruct.new(item_index: 'chain-mail', item_name: 'Cota de Malha')

      out = EquipmentRules.ac_for(sheet: sheet, armor_item: cota, shield_item: comum)

      expect(out[:stealth_disadvantage]).to be(true)
    end
  end
end
