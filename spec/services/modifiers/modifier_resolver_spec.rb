# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Modifiers::ModifierResolver, type: :service do
  let(:sheet) do
    instance_double('Sheet',
      id: 1,
      metadata: metadata,
      sheet_klasses: sheet_klasses,
    )
  end
  let(:metadata) { {} }
  let(:sheet_klasses) { [] }
  let(:context) { {} }
  # Restringimos aos producers que não tocam ActiveRecord pesado neste spec.
  # KlassProducer e EquippedItemProducer são exercidos via integração no
  # smoke test do CharacterSheetSummaryService.
  subject(:resolver) { described_class.new(sheet, context: context, producer_keys: [:feat]) }

  describe '#call' do
    it 'retorna um Bag vazio quando não há producers com matches' do
      bag = resolver.call
      expect(bag).to be_a(Modifiers::ModifierResolver::Bag)
      expect(bag.size).to eq(0)
    end

    context 'com feat Resiliente' do
      let(:metadata) do
        { 'feats' => [{ 'feat_id' => 'resiliente', 'choices' => { 'saving_throws' => 'con' } }] }
      end

      it 'gera grant em save.con' do
        bag = resolver.call
        expect(bag.granted('save')).to include('con')
      end
    end

    context 'com feat Robusto' do
      let(:metadata) { { 'feats' => [{ 'feat_id' => 'robusto' }] } }

      it 'gera +2 em hp.max_per_level' do
        bag = resolver.call
        expect(bag.sum_for('hp.max_per_level')).to eq(2)
      end
    end

    context 'com feat Mobilidade' do
      let(:metadata) { { 'feats' => [{ 'feat_id' => 'mobilidade' }] } }

      it 'gera +10 ft em speed' do
        bag = resolver.call
        expect(bag.sum_for('speed')).to eq(10)
      end
    end

    context 'com Robusto + Tough (mesmo target untyped)' do
      let(:metadata) do
        { 'feats' => [{ 'feat_id' => 'robusto' }, { 'feat_id' => 'tough' }] }
      end

      it 'soma untyped (4)' do
        bag = resolver.call
        expect(bag.sum_for('hp.max_per_level')).to eq(4)
      end
    end
  end

  describe Modifiers::ModifierResolver::Bag do
    let(:m1) do
      Modifiers::Modifier.new(
        target: 'ac', op: :add, value: 2, source: 'item:a', source_kind: :item,
        stacking_type: 'magico',
      )
    end
    let(:m2) do
      Modifiers::Modifier.new(
        target: 'ac', op: :add, value: 1, source: 'item:b', source_kind: :item,
        stacking_type: 'magico',
      )
    end
    let(:m3) do
      Modifiers::Modifier.new(
        target: 'ac', op: :add, value: 3, source: 'feat:x', source_kind: :feat,
        stacking_type: 'untyped',
      )
    end

    it 'aplica typed stacking (apenas o maior magico) e soma untypeds livremente' do
      bag = described_class.new([m1, m2, m3])
      # untyped: 3, magico (max): 2 → total: 5
      expect(bag.sum_for('ac')).to eq(5)
    end

    # Bug #2 Adimael: a aba "Efeitos de Itens Equipados" exibia +10 ft do feat
    # Mobilidade porque `summary[:modifiers][:speed_bonus]` somava TODAS as
    # origens. Bag#sum_for_kind permite separar bônus por `source_kind`
    # (`:item`, `:feat`, etc.), mantendo `sum_for` como soma geral
    # (compativel com `movement[:speed_ft]` total).
    describe '#sum_for_kind' do
      let(:speed_item) do
        Modifiers::Modifier.new(
          target: 'speed', op: :add, value: 5, source: 'item:botas',
          source_kind: :item, stacking_type: 'magico',
        )
      end
      let(:speed_feat) do
        Modifiers::Modifier.new(
          target: 'speed', op: :add, value: 10, source: 'feat:mobilidade',
          source_kind: :feat, stacking_type: 'untyped',
        )
      end
      let(:bag) { described_class.new([speed_item, speed_feat]) }

      it 'soma apenas modifiers do source_kind pedido' do
        expect(bag.sum_for_kind('speed', source_kind: :item)).to eq(5)
        expect(bag.sum_for_kind('speed', source_kind: :feat)).to eq(10)
      end

      it 'aceita Array de source_kinds' do
        expect(bag.sum_for_kind('speed', source_kind: [:item, :feat])).to eq(15)
      end

      it 'devolve 0 quando nenhum modifier casa o source_kind' do
        expect(bag.sum_for_kind('speed', source_kind: :race)).to eq(0)
      end

      it 'mantem typed stacking (so o maior magico por kind)' do
        magic_boots = Modifiers::Modifier.new(
          target: 'ac', op: :add, value: 2, source: 'item:a',
          source_kind: :item, stacking_type: 'magico',
        )
        magic_shield = Modifiers::Modifier.new(
          target: 'ac', op: :add, value: 1, source: 'item:b',
          source_kind: :item, stacking_type: 'magico',
        )
        feat_ac = Modifiers::Modifier.new(
          target: 'ac', op: :add, value: 3, source: 'feat:x',
          source_kind: :feat, stacking_type: 'untyped',
        )
        b = described_class.new([magic_boots, magic_shield, feat_ac])
        expect(b.sum_for_kind('ac', source_kind: :item)).to eq(2)
        expect(b.sum_for_kind('ac', source_kind: :feat)).to eq(3)
        expect(b.sum_for('ac')).to eq(5)
      end
    end
  end
end
