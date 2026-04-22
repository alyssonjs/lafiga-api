# frozen_string_literal: true

require 'rails_helper'

# P2.14 — Schema estendido `recharge_at_level`.
#
# Alguns recursos mudam de recarga em determinado nivel de classe (ex:
# bardic_inspiration eh LR ate nv 4 e SR a partir do nv 5 — Font of
# Inspiration, PHB pg. 54). Este spec trava o contrato do
# ResourceCatalog.recharge_for(key, level:) e do
# short_rest_keys(level:).
RSpec.describe Sheets::Runtime::ResourceCatalog do
  before { described_class.reload! }
  after  { described_class.reload! }

  describe '.recharge_for' do
    it 'sem nivel: retorna o recharge base do YAML' do
      expect(described_class.recharge_for('bardic_inspiration')).to eq('long')
      expect(described_class.recharge_for('rage')).to eq('long')
      expect(described_class.recharge_for('ki')).to eq('short')
    end

    it 'com nivel < trigger override: continua usando base' do
      expect(described_class.recharge_for('bardic_inspiration', level: 4)).to eq('long')
    end

    it 'com nivel >= trigger override: aplica override' do
      expect(described_class.recharge_for('bardic_inspiration', level: 5)).to eq('short')
      expect(described_class.recharge_for('bardic_inspiration', level: 11)).to eq('short')
      expect(described_class.recharge_for('bardic_inspiration', level: 20)).to eq('short')
    end

    it 'recurso sem overrides nao eh afetado por nivel' do
      expect(described_class.recharge_for('rage', level: 1)).to eq('long')
      expect(described_class.recharge_for('rage', level: 20)).to eq('long')
      expect(described_class.recharge_for('ki', level: 20)).to eq('short')
    end

    it 'chave desconhecida retorna nil' do
      expect(described_class.recharge_for('unknown_xyz')).to be_nil
    end
  end

  describe '.short_rest_keys(level:)' do
    it 'sem nivel: NAO inclui bardic_inspiration (base = long)' do
      expect(described_class.short_rest_keys).not_to include('bardic_inspiration')
    end

    it 'level 4: ainda nao inclui bardic_inspiration' do
      expect(described_class.short_rest_keys(level: 4)).not_to include('bardic_inspiration')
    end

    it 'level 5: inclui bardic_inspiration (override aplicado)' do
      expect(described_class.short_rest_keys(level: 5)).to include('bardic_inspiration')
    end

    it 'continua incluindo recursos sempre-SR (ki, channel_divinity, etc.)' do
      keys = described_class.short_rest_keys(level: 5)
      expect(keys).to include('ki', 'channel_divinity', 'second_wind', 'action_surge', 'wild_shape')
    end
  end
end
