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

# ===== TREINAMENTO EM HORAS (10/09/2026) =====
#
# Aprender proficiência custa HORAS. Nem toda proficiência é treinável: idioma
# secreto de classe e "Armas Simples" vêm com a classe, não com treino.
RSpec.describe 'Proficiency — treinamento' do
  def cria(meta)
    Proficiency.new(api_index: 'tool-x', name: 'X', category: 'tool', sub_category: 'artisan', metadata: meta)
  end

  describe '#trainable?' do
    it '⚠️ ausente conta como NÃO' do
      # As 142 linhas semeadas antes disto existir não podem virar treináveis
      # por omissão — seria dar ao jogador um caminho que ninguém definiu.
      expect(cria({}).trainable?).to be(false)
      expect(cria(nil).trainable?).to be(false)
      expect(cria('trainable' => true).trainable?).to be(true)
    end
  end

  describe '#training_hours' do
    it 'devolve as horas quando treinável' do
      expect(cria('trainable' => true, 'training_hours' => 120).training_hours).to eq(120)
    end

    it 'devolve nil quando NÃO é treinável, mesmo com horas gravadas' do
      # Desmarcar "treinável" tem de bastar; não pode depender de alguém
      # lembrar de limpar as horas também.
      expect(cria('trainable' => false, 'training_hours' => 120).training_hours).to be_nil
    end

    it 'devolve nil quando as horas ainda não foram definidas' do
      expect(cria('trainable' => true).training_hours).to be_nil
    end
  end

  describe '#trained?' do
    let(:p) { cria('trainable' => true, 'training_hours' => 120) }

    it 'a hora exata JÁ conta' do
      expect(p.trained?(119)).to be(false)
      expect(p.trained?(120)).to be(true)
      expect(p.trained?(500)).to be(true)
    end

    it 'sem horas definidas, ninguém está treinado' do
      # ⚠️ `nil` é "por definir", e por definir não pode virar "já sabe".
      expect(cria('trainable' => true).trained?(9_999)).to be(false)
    end

    it 'não treinável nunca está "treinado" — vem por outro caminho' do
      expect(cria('trainable' => false).trained?(9_999)).to be(false)
    end
  end

  describe 'validação das horas' do
    it '⚠️ zero não é "de graça", é engano' do
      # Treinável com 0 horas seria aprendida sem treino nenhum, e o erro só
      # apareceria na mesa.
      p = cria('trainable' => true, 'training_hours' => 0)
      expect(p).not_to be_valid
      expect(p.errors[:metadata].join).to match(/positivas/)
    end

    it 'negativo também não' do
      expect(cria('trainable' => true, 'training_hours' => -5)).not_to be_valid
    end

    it '⚠️ mas VAZIO é diferente de zero: significa "ainda por definir"' do
      expect(cria('trainable' => true)).to be_valid
      expect(cria('trainable' => true, 'training_hours' => nil)).to be_valid
    end

    it 'recusa o formato antigo de escada' do
      # Sobrou de quando havia degraus (aprendiz/intermediário/mestre/perito).
      p = cria('trainable' => true, 'training_hours' => { 'aprendiz' => 50 })
      expect(p).not_to be_valid
      expect(p.errors[:metadata].join).to match(/número de horas/)
    end

    it 'aceita as horas bem formadas' do
      expect(cria('trainable' => true, 'training_hours' => 120)).to be_valid
    end
  end
end
