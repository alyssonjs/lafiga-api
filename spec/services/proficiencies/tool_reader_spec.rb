# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# FASE 1 de FERRAMENTA — quem lê resolve pelo catálogo, não pela grafia.
#
# ⚠️ Diferente do idioma: lá o que estava gravado já era canônico e a mudança
# foi invisível. Aqui NÃO é. As fichas guardam "Gaita de Foles", "Veículos
# Terrestres", "Ferramentas de Artesão (Cozinheiro)" — e canonicalizar MUDA o
# texto na tela de 34 das 69 fichas. Todas para melhor, mas é mudança visível,
# não paridade.
RSpec.describe Proficiencies::ToolReader do
  before(:all) do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  before do
    Proficiency.where(category: %w[tool vehicle]).destroy_all
    described_class.reset_cache!
    Rake::Task['dnd:seed_proficiency_tools'].reenable
    Rake::Task['dnd:seed_proficiency_tools'].invoke
    described_class.reset_cache!
  end

  after { described_class.reset_cache! }

  describe '⚠️ aceita ferramenta E veículo' do
    it 'porque a ficha sempre guardou os dois no MESMO array' do
      # No catálogo veículo é tipo próprio, mas `class_summary.tools` nunca
      # separou. Um leitor só de `tool` deixaria "Veículos Terrestres" órfão —
      # justamente a proficiência que já custou 14 órfãs por grafia.
      out = described_class.canonicalize(['Ferramentas de Ladrão', 'Veículos Terrestres'])
      expect(out).to eq(['Ferramentas de ladrão', 'Veículos (terrestres)'])
    end
  end

  describe 'o que muda na tela, e por quê' do
    it 'caixa diferente vira o nome canônico' do
      expect(described_class.canonicalize(['Gaita de Foles'])).to eq(['Gaita de foles'])
    end

    it 'o prefixo legado do wizard é resolvido' do
      # "Ferramentas de Artesão (Cozinheiro)" era uma forma antiga do wizard.
      expect(described_class.canonicalize(['Ferramentas de Artesão (Cozinheiro)']))
        .to eq(['Utensílios de cozinheiro'])
    end

    it 'o nome do livro cai no nome em uso' do
      expect(described_class.canonicalize(['Ferramentas de Coureiro']))
        .to eq(['Ferramentas de curtidor'])
    end

    it '⚠️ duas grafias da MESMA ferramenta viram UMA linha' do
      # A ficha 95 mostrava "Kit de Herbalismo" e "Kit de herbalismo" como duas
      # proficiências. `Array#uniq` não colapsava; a identidade canônica sim.
      out = described_class.canonicalize(['Kit de Herbalismo', 'Kit de herbalismo'])
      expect(out).to eq(['Kit de herbalismo'])
      expect(['Kit de Herbalismo', 'Kit de herbalismo'].uniq.size).to eq(2) # o de antes
    end

    it 'as quatro grafias de veículo convergem' do
      out = described_class.canonicalize(
        ['Veículos Terrestres', 'Veículos (terrestres)', 'Veículos (terrestre)', 'vehicles_land'],
      )
      expect(out).to eq(['Veículos (terrestres)'])
    end
  end

  describe '⚠️ o prefixo "Jogo de " — recuperável vs. slot errado' do
    it 'quando o miolo É conjunto de jogo, a proficiência é PRESERVADA' do
      # `background_rules.rb:326` monta `'Jogo de ' + label`. Descartar estes
      # tiraria do jogador o que o antecedente concedeu.
      expect(described_class.canonicalize(['Jogo de Dados'])).to eq(['Conjunto de dados'])
      expect(described_class.canonicalize(['Jogo de Cartas'])).to eq(['Baralho de cartas'])
      expect(described_class.canonicalize(['Jogo de Xadrez de dragão'])).to eq(['Xadrez de dragão'])
    end

    it 'quando NÃO é, passa intacto — adivinhar seria inventar' do
      # A fila de escolhas entregou o slot errado; não dá para saber o que o
      # jogador escolheu. A auditoria o reporta em quarentena.
      expect(described_class.canonicalize(['Jogo de Veículos Terrestres']))
        .to eq(['Jogo de Veículos Terrestres'])
    end
  end

  describe 'as garantias da base valem aqui também' do
    it 'TOLERANTE — o não catalogado não se perde' do
      expect(described_class.canonicalize(['Lira', 'Kit de Bruxaria']))
        .to eq(['Lira', 'Kit de Bruxaria'])
    end

    it 'PRESERVA A ORDEM' do
      expect(described_class.canonicalize(['Lira', 'Alaúde'])).to eq(%w[Lira Alaúde])
      expect(described_class.canonicalize(['Alaúde', 'Lira'])).to eq(%w[Alaúde Lira])
    end

    it 'DEGRADA PARA IDENTIDADE com o catálogo vazio' do
      Proficiency.where(category: %w[tool vehicle]).destroy_all
      described_class.reset_cache!
      expect(described_class.canonicalize(['Gaita de Foles'])).to eq(['Gaita de Foles'])
    end

    it '⚠️ e o leitor de IDIOMA não enxerga ferramenta' do
      # As categorias são o que separa os leitores; sem isso o catálogo perderia
      # a razão de existir.
      expect(Proficiencies::LanguageReader.canonicalize(['Gaita de Foles']))
        .to eq(['Gaita de Foles'])
    end
  end
end
