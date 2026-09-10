# frozen_string_literal: true

require 'rails_helper'

# FASE 1 — quem LÊ idioma resolve pelo catálogo, não pela grafia exata.
#
# Nada aqui muda o que é GRAVADO. O ponto é que a leitura deixe de depender de
# alguém ter digitado o acento certo — que é o modo de falha que órfãou 14
# proficiências sem ninguém notar.
RSpec.describe Proficiencies::LanguageReader do
  before { described_class.reset_cache! }
  after  { described_class.reset_cache! }

  def catalogar(nome, sub = 'standard', apelidos = [])
    p = Proficiency.create!(api_index: "lang-#{Proficiency.normalize(nome).tr(' ', '-')}",
                            name: nome, category: 'language', sub_category: sub)
    ([nome] + apelidos).each { |a| p.add_alias!(a) }
    p
  end

  describe 'resolve pela grafia, qualquer que seja' do
    before { catalogar('Élfico') }

    it 'devolve o nome CANÔNICO, não o que estava escrito' do
      expect(described_class.canonicalize(['elfico'])).to eq(['Élfico'])
      expect(described_class.canonicalize(['  ÉLFICO  '])).to eq(['Élfico'])
    end

    it '⚠️ colapsa duas grafias do MESMO idioma numa linha só' do
      # É a diferença concreta em relação ao `.uniq` de antes, que via duas
      # strings diferentes e mostrava as duas na ficha.
      expect(described_class.canonicalize(%w[Élfico elfico ELFICO])).to eq(['Élfico'])
      expect(%w[Élfico elfico ELFICO].uniq.size).to eq(3) # o que acontecia antes
    end
  end

  describe '⚠️ TOLERANTE — o não catalogado NÃO se perde' do
    before { catalogar('Comum') }

    it 'passa intacto, na posição em que estava' do
      # Descartar seria trocar um defeito silencioso por outro pior. Quem
      # aponta o não-catalogado é a auditoria, não o leitor.
      expect(described_class.canonicalize(['Comum', 'Klingon'])).to eq(%w[Comum Klingon])
    end

    it 'dois não catalogados que só diferem no acento também colapsam' do
      expect(described_class.canonicalize(['Klíngon', 'klingon'])).to eq(['Klíngon'])
    end
  end

  describe '⚠️ DEGRADA PARA IDENTIDADE com o catálogo vazio' do
    it 'devolve a entrada como está' do
      # O código sobe para produção ANTES de o rake de seed rodar. Sem esta
      # propriedade, a janela entre os dois deixaria toda ficha sem idioma.
      expect(Proficiency.of('language').count).to eq(0)
      expect(described_class.canonicalize(%w[Comum Élfico])).to eq(%w[Comum Élfico])
    end
  end

  describe 'PRESERVA A ORDEM' do
    it 'primeira ocorrência vence' do
      catalogar('Comum')
      catalogar('Anão')
      # A ficha não pode reembaralhar a lista de idiomas só porque passou a
      # resolver pelo catálogo.
      expect(described_class.canonicalize(['Anão', 'Comum'])).to eq(['Anão', 'Comum'])
      expect(described_class.canonicalize(['Comum', 'Anão'])).to eq(['Comum', 'Anão'])
    end
  end

  describe 'higiene da entrada' do
    before { catalogar('Comum') }

    it 'descarta vazio e nil sem estourar' do
      expect(described_class.canonicalize(['Comum', '', '   ', nil])).to eq(['Comum'])
      expect(described_class.canonicalize(nil)).to eq([])
    end
  end

  describe '#detail' do
    before { catalogar('Aquan', 'primordial_dialect') }

    it 'acrescenta a estrutura do catálogo e marca o que não é catalogado' do
      d = described_class.detail(%w[Aquan Klingon])
      expect(d.first).to include('name' => 'Aquan', 'api_index' => 'lang-aquan',
                                 'sub_category' => 'primordial_dialect', 'catalogued' => true)
      expect(d.last).to include('name' => 'Klingon', 'catalogued' => false, 'api_index' => nil)
    end
  end

  describe 'cache' do
    it 'enxerga linha nova sem precisar de reset manual' do
      # A assinatura é (contagem, maior updated_at) — semear pelo rake em
      # produção não pode exigir reiniciar o processo.
      expect(described_class.canonicalize(['elfico'])).to eq(['elfico'])
      catalogar('Élfico')
      expect(described_class.canonicalize(['elfico'])).to eq(['Élfico'])
    end
  end
end
