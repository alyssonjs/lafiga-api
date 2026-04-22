require 'rails_helper'

RSpec.describe Sheets::Runtime::ResourceCatalog do
  describe '.all' do
    it 'carrega config/class_resources.yml e retorna um Hash' do
      catalog = described_class.all
      expect(catalog).to be_a(Hash)
      expect(catalog).not_to be_empty
    end

    it 'cada entrada tem chave recharge ("short" ou "long")' do
      described_class.all.each do |key, def_|
        expect(%w[short long]).to include(def_['recharge']),
          -> { "key '#{key}' tem recharge invalido: #{def_['recharge'].inspect}" }
      end
    end
  end

  describe '.short_rest_keys' do
    it 'inclui ki, channel_divinity, second_wind, action_surge, wild_shape' do
      sr = described_class.short_rest_keys
      expect(sr).to include('ki', 'channel_divinity', 'second_wind', 'action_surge', 'wild_shape')
    end

    it 'NAO inclui rage (que recarrega em LR)' do
      expect(described_class.short_rest_keys).not_to include('rage')
    end
  end

  describe '.long_rest_keys' do
    it 'retorna TODAS as chaves do catalogo (regra: tudo SR tambem LR)' do
      expect(described_class.long_rest_keys.sort).to eq(described_class.all.keys.sort)
    end
  end

  describe '.known?' do
    it 'eh true para chaves conhecidas' do
      expect(described_class.known?('rage')).to be(true)
      expect(described_class.known?(:rage)).to be(true)
    end

    it 'eh false para chaves desconhecidas' do
      expect(described_class.known?('inexistente_xyz')).to be(false)
    end
  end
end
