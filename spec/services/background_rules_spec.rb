# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BackgroundRules do
  describe '.find' do
    it 'resolves string slugs to RULES entries (symbol keys in RULES hash)' do
      bg = described_class.find('acolyte')
      expect(bg).to be_a(Hash)
      expect(bg[:id]).to eq('acolyte')
      expect(bg[:equipment]).to be_an(Array)
      expect(bg[:equipment].first).to include('símbolo')
    end

    it 'resolves symbol keys' do
      bg = described_class.find(:acolyte)
      expect(bg[:name]).to eq('Acólito')
    end
  end

  describe '.apply' do
    it 'returns equipment list for acolyte' do
      summary = described_class.apply(key: 'acolyte', choices: { languages: %w[Goblin Halfling] })
      expect(summary[:equipment].size).to be >= 5
      expect(summary[:equipment]).to include(a_string_matching(/símbolo/i))
    end

    it 'resolves outlander instrument from choices[:tools] queue' do
      summary = described_class.apply(
        key: 'outlander',
        choices: { tools: ['Flauta'] }
      )
      expect(summary[:tools]).to include('Flauta')
    end

    it 'resolves noble gaming set from choices[:tools] queue' do
      summary = described_class.apply(
        key: 'noble',
        choices: { tools: ['Baralho de cartas'] }
      )
      expect(summary[:tools].first).to eq('Jogo de Baralho de cartas')
    end
  end
end
