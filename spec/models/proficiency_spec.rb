# frozen_string_literal: true

require 'rails_helper'

# O catálogo existe para tirar a proficiência do limbo da string livre.
#
# Antes dele, as ~1.004 proficiências das fichas eram texto solto dentro de
# jsonb — sem chave estrangeira, sem validação, e um erro de grafia falhando em
# SILÊNCIO: a linha só não aparecia na ficha. Foi assim que "Veículos
# terrestres" acabou com quatro grafias e 14 proficiências ficaram órfãs.
RSpec.describe Proficiency do
  describe '.normalize — a régua única de comparação' do
    it 'ignora acento, caixa e espaço' do
      %w[Élfico élfico ELFICO].each { |v| expect(described_class.normalize(v)).to eq('elfico') }
      expect(described_class.normalize('  Gíria   de  Ladrão ')).to eq('giria de ladrao')
    end

    it '⚠️ colapsa a pontuação — é o que faz "Thieves\' Cant" casar' do
      expect(described_class.normalize("Thieves' Cant")).to eq('thieves cant')
    end

    it 'string vazia continua vazia (não vira apelido curinga)' do
      expect(described_class.normalize('   ')).to eq('')
      expect(described_class.normalize(nil)).to eq('')
    end
  end

  describe '#add_alias! e .resolve' do
    let!(:idioma) { described_class.create!(api_index: 'lang-x', name: 'Élfico', category: 'language', sub_category: 'standard') }

    it 'resolve pela grafia exata e pelas variantes' do
      idioma.add_alias!('Élfico')
      expect(described_class.resolve('Élfico')).to eq(idioma)
      expect(described_class.resolve('elfico')).to eq(idioma)
      expect(described_class.resolve('  ÉLFICO ')).to eq(idioma)
    end

    it 'é idempotente — semear duas vezes não duplica apelido' do
      idioma.add_alias!('Élfico')
      expect { idioma.add_alias!('Élfico') }.not_to change(ProficiencyAlias, :count)
      expect { idioma.add_alias!('elfico') }.not_to change(ProficiencyAlias, :count)
    end

    it '⚠️ apelido disputado LEVANTA em vez de mudar de dono em silêncio' do
      idioma.add_alias!('Élfico')
      outro = described_class.create!(api_index: 'lang-y', name: 'Outro', category: 'language', sub_category: 'standard')
      # Roubar o apelido calado é exatamente como a proficiência somia da ficha
      # sem ninguém notar. Doer é o comportamento desejado.
      expect { outro.add_alias!('elfico') }.to raise_error(ArgumentError, /já aponta para/)
    end

    it 'string vazia não vira apelido' do
      expect { idioma.add_alias!('  ') }.not_to change(ProficiencyAlias, :count)
    end

    it 'não catalogado devolve nil, e resolve! levanta' do
      expect(described_class.resolve('Klingon')).to be_nil
      expect { described_class.resolve!('Klingon') }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'a categoria restringe a busca' do
      idioma.add_alias!('Élfico')
      expect(described_class.resolve('Élfico', category: 'language')).to eq(idioma)
      expect(described_class.resolve('Élfico', category: 'tool')).to be_nil
    end
  end

  describe 'validações' do
    it 'recusa categoria fora do vocabulário' do
      p = described_class.new(api_index: 'x', name: 'X', category: 'inventada')
      expect(p).not_to be_valid
      expect(p.errors[:category]).to be_present
    end

    it 'recusa sub-categoria que não pertence à categoria' do
      p = described_class.new(api_index: 'x', name: 'X', category: 'language', sub_category: 'artisan')
      expect(p).not_to be_valid
      expect(p.errors[:sub_category]).to be_present
    end

    it 'aceita sub-categoria vazia onde a categoria não subdivide' do
      expect(described_class.new(api_index: 'x', name: 'X', category: 'skill')).to be_valid
    end
  end
end
