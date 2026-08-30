require 'rails_helper'

RSpec.describe SheetItem, type: :model do
  describe 'slot validation (Fase 2.1 — accessory slots)' do
    # Subclasse leve só para teste: remove o `belongs_to :sheet` (não queremos
    # depender do schema completo de Sheet) e desliga validações alheias ao slot.
    before(:all) do
      Object.const_set(:SheetItemSlotTest, Class.new(SheetItem) do
        self.table_name = 'sheet_items'
        clear_validators!
        validates :slot, inclusion: { in: SheetItem::ALL_SLOTS, allow_nil: true }
      end)
    end
    after(:all) do
      Object.send(:remove_const, :SheetItemSlotTest) if Object.const_defined?(:SheetItemSlotTest)
    end
    let(:item) { SheetItemSlotTest.new(item_name: 'Item Teste', quantity: 1) }

    it 'aceita slots de combate clássicos' do
      SheetItem::COMBAT_SLOTS.each do |slot|
        item.slot = slot
        expect(item.valid?).to eq(true), "Slot '#{slot}' deveria ser aceito. Erros[:slot]: #{item.errors[:slot]}"
      end
    end

    it 'aceita todos os accessory slots novos' do
      SheetItem::ACCESSORY_SLOTS.each do |slot|
        item.slot = slot
        expect(item.valid?).to eq(true), "Slot '#{slot}' deveria ser aceito. Erros[:slot]: #{item.errors[:slot]}"
      end
    end

    it 'aceita o slot utilitário da aljava' do
      item.slot = 'quiver'
      expect(item.valid?).to eq(true)
    end

    it 'aceita slot nulo (item não equipado)' do
      item.slot = nil
      expect(item.valid?).to eq(true)
    end

    it 'rejeita slots desconhecidos' do
      item.slot = 'underwear'
      expect(item.valid?).to eq(false)
      expect(item.errors[:slot]).to be_present
    end

    it 'expõe ALL_SLOTS combinando combate + acessórios + utilitários' do
      expect(SheetItem::ALL_SLOTS).to eq(
        SheetItem::COMBAT_SLOTS + SheetItem::ACCESSORY_SLOTS + SheetItem::UTILITY_SLOTS
      )
      expect(SheetItem::ALL_SLOTS).to include('main_hand', 'off_hand', 'armor', 'shield')
      # 29/08: `face` (rosto) entrou; `circlet` foi FUNDIDO em `helmet`.
      expect(SheetItem::ALL_SLOTS).to include('ring_left', 'ring_right', 'amulet', 'cloak',
                                              'boots', 'helmet', 'gloves', 'belt',
                                              'face', 'earrings', 'bracelet_left', 'bracelet_right')
      # 30/08: `quiver` e `bag` FUNDIDOS em `back` (Costas) — é o mesmo lugar
      # do corpo, e leva uma coisa de cada vez.
      expect(SheetItem::ALL_SLOTS).to include('back')
      expect(SheetItem::ALL_SLOTS).not_to include('quiver', 'bag')
    end
  end
end
