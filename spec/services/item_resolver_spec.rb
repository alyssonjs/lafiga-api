# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ItemResolver do
  let(:resolver) { described_class.new }

  describe '#resolve' do
    context 'quando o Item ja existe no catalogo' do
      let!(:dagger) { Item.find_or_create_by!(api_index: 'adaga') { |i| i.name = 'Adaga'; i.kind = 'weapon' } }

      it 'reusa o registro existente para o nome canonico' do
        expect(resolver.resolve(name: 'Adaga')).to eq(dagger)
      end

      it 'reusa o registro existente case-insensitive' do
        expect(resolver.resolve(name: 'adaga')).to eq(dagger)
      end

      it 'nao cria duplicata' do
        before_count = Item.count
        2.times { resolver.resolve(name: 'Adaga') }
        expect(Item.count).to eq(before_count)
      end
    end

    context 'quando bate na EquipmentRules::WEAPON_TABLE' do
      it 'mapeia "Claive" (typo do excel) para api_index canonico glaive com kind=weapon' do
        item = resolver.resolve(name: 'Claive', category: 'Armas')
        expect(item).to be_persisted
        expect(item.api_index).to eq('glaive')
        expect(item.kind).to eq('weapon')
      end
    end

    context 'quando o catalogo ainda nao tem mas a categoria diz que e armadura' do
      it 'infere kind=armor a partir da category' do
        unique = "spec-armor-#{SecureRandom.hex(4)}"
        item = resolver.resolve(name: unique, category: 'Armaduras & Escudos')
        expect(item.kind).to eq('armor')
      end
    end

    context 'quando nao bate em nada conhecido' do
      it 'cria Item com kind=gear como fallback' do
        unique = "Cinto Spec #{SecureRandom.hex(4)}"
        item = resolver.resolve(name: unique, category: nil)
        expect(item).to be_persisted
        expect(item.api_index).to start_with('cinto-spec-')
        expect(item.kind).to eq('gear')
      end

      it 'infere kind=book quando nome contem "livro"' do
        unique = "Livro Spec #{SecureRandom.hex(4)}"
        item = resolver.resolve(name: unique, category: nil)
        expect(item.kind).to eq('book')
      end

      it 'infere kind=consumable accent-agnostic ("Ração" -> racao -> consumable)' do
        unique = "Ração Spec #{SecureRandom.hex(4)}"
        item = resolver.resolve(name: unique, category: nil)
        expect(item.kind).to eq('consumable')
      end
    end

    context 'inputs invalidos' do
      it 'retorna nil para nome vazio' do
        expect(resolver.resolve(name: '')).to be_nil
      end

      it 'retorna nil para nome puramente numerico' do
        expect(resolver.resolve(name: '2.0')).to be_nil
      end
    end
  end

  describe 'integracao com SheetItem (callback before_validation)' do
    let(:user)      { FactoryBot.create(:user) }
    let(:character) { FactoryBot.create(:character, user: user) }
    let(:sheet)     { character.sheet || FactoryBot.create(:sheet, character: character) }

    it 'auto-resolve item_id ao salvar via SheetItem.create!' do
      si = SheetItem.create!(
        sheet: sheet,
        item_name: 'Adaga',
        quantity: 1,
        category: 'Armas',
        source: 'spec'
      )
      expect(si.item_id).to be_present
      expect(si.item.kind).to eq('weapon')
      expect(si.item_index).to eq('adaga')
    end

    it 'respeita item_id ja informado pelo caller' do
      explicit = Item.find_or_create_by!(api_index: 'spec-custom-item') do |i|
        i.name = 'Spec Custom'
        i.kind = 'gear'
      end
      si = SheetItem.create!(
        sheet: sheet,
        item_id: explicit.id,
        item_name: 'Spec Custom',
        quantity: 1,
        source: 'spec'
      )
      expect(si.item_id).to eq(explicit.id)
    end

    it 'nao falha quando o nome e in-utilizavel — apenas deixa item_id em nil' do
      si = SheetItem.new(sheet: sheet, item_name: '2.0', quantity: 1, source: 'spec')
      si.valid?
      expect(si.item_id).to be_nil
    end
  end
end
