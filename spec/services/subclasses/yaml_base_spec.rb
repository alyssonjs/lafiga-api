# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subclasses::YamlBase do
  describe '.mapa' do
    it 'chaveia pelo api_index de DESTINO, o mesmo que o import grava' do
      expect(described_class.mapa('fighter')).to include('campeao', 'mestre-de-batalha')
    end

    it 'não deixa a chave do YAML vazar quando existe alias' do
      aliases = DndImportHelpers::SUBCLASS_ALIASES['barbarian'] || {}
      chaves = described_class.mapa('barbarian').keys

      expect(chaves & aliases.keys).to eq([])
      expect(aliases.values & chaves).not_to be_empty
    end

    it 'não trata `rules`/`boons`/`invocations` do bruxo como arquétipo' do
      expect(described_class.mapa('warlock').keys).not_to include('rules', 'boons', 'invocations')
    end

    it 'devolve {} para classe que o YAML não conhece' do
      expect(described_class.mapa('classe-que-nao-existe')).to eq({})
    end
  end

  describe '.linhas' do
    it 'devolve as linhas do livro, todas com `level`' do
      linhas = described_class.linhas('fighter', 'campeao')

      expect(linhas).not_to be_empty
      expect(linhas).to all(be_a(Hash))
      expect(linhas.map { |l| l['level'] }).to all(be_a(Integer))
    end

    it 'devolve [] para sub-classe inexistente — homebrew não tem base' do
      expect(described_class.linhas('fighter', 'arquetipo-caseiro')).to eq([])
    end
  end

  describe '.destino' do
    it 'passa pela tabela de alias do import' do
      expect(described_class.destino('barbarian', 'caminho-do-furioso')).to eq('berserker')
    end

    it 'sem alias, o destino é a própria chave' do
      expect(described_class.destino('fighter', 'campeao')).to eq('campeao')
    end
  end
end
