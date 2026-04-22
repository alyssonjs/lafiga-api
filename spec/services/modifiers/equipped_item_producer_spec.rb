# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Modifiers::Producers::EquippedItemProducer, type: :service do
  let(:sheet) { instance_double('Sheet', id: 1) }

  def producer_for(mi_hash)
    rules = instance_double('MagicItemRules', call: mi_hash)
    allow(MagicItemRules).to receive(:new).and_return(rules)
    described_class.new(sheet, context: { equipment: {} })
  end

  it 'emite weapon.attack/damage por slot com predicate' do
    mi = {
      ac_bonus: 0, weapon_mods: {
        main_hand: { attack: 2, damage: 1, is_magical: true },
        off_hand:  { attack: 0, damage: 0, is_magical: false },
      },
    }
    mods = producer_for(mi).produce
    targets = mods.map(&:target).sort
    expect(targets).to include('weapon.attack', 'weapon.damage')
    atk = mods.find { |m| m.target == 'weapon.attack' }
    expect(atk.value).to eq(2)
    expect(atk.predicate).to eq('weapon.slot' => 'main_hand')
    expect(atk.stacking_type).to eq('magico')
  end

  it 'emite ac com stacking_type magico' do
    mods = producer_for(ac_bonus: 1, weapon_mods: {}).produce
    ac = mods.find { |m| m.target == 'ac' }
    expect(ac).not_to be_nil
    expect(ac.value).to eq(1)
    expect(ac.stacking_type).to eq('magico')
  end

  it 'emite resistance e save_advantage como :grant' do
    mi = {
      ac_bonus: 0, weapon_mods: {},
      resistances: ['fogo', 'frio'],
      save_advantages: ['wis', 'cha'],
    }
    mods = producer_for(mi).produce
    grants = mods.select { |m| m.op == :grant }
    expect(grants.map(&:target)).to include(
      'resistance.fogo', 'resistance.frio',
      'advantage.save.wis', 'advantage.save.cha',
    )
  end

  it 'emite ability.set para attribute_set e respeita typed magico' do
    mi = {
      ac_bonus: 0, weapon_mods: {},
      ability_sets: { 'str' => 19 },
    }
    mods = producer_for(mi).produce
    set_str = mods.find { |m| m.target == 'ability.str' && m.op == :set }
    expect(set_str).not_to be_nil
    expect(set_str.value).to eq(19)
  end

  it 'emite speed.add' do
    mi = { ac_bonus: 0, weapon_mods: {}, speed_bonus: 10 }
    mods = producer_for(mi).produce
    sp = mods.find { |m| m.target == 'speed' }
    expect(sp.value).to eq(10)
    expect(sp.op).to eq(:add)
  end

  it 'emite passive_feature como :grant com value Hash' do
    mi = {
      ac_bonus: 0, weapon_mods: {},
      passive_features: [{ source: 'botas', name: 'Asas', desc: 'voa' }],
    }
    mods = producer_for(mi).produce
    pf = mods.find { |m| m.target == 'passive_feature' }
    expect(pf).not_to be_nil
    expect(pf.value).to include(name: 'Asas')
  end
end
