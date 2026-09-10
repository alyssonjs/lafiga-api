# frozen_string_literal: true

require 'rails_helper'
require 'rake'
require 'yaml'

# ⚠️ AS TRÊS LISTAS RIVAIS DE IDIOMA
#
# O cabeçalho de `front-lafiga/src/app/data/languageCatalog.ts` registrava, em
# texto, que existiam outras duas listas no backend (`config/race_rules.yml` e
# `background_rules.rb`) que NUNCA foram reconciliadas — e que o servidor aceita
# o que o front mandar, porque `picks_taken` não valida contra `choiceList`.
#
# Este guarda é o que impede a divergência de voltar: toda opção que o backend
# OFERECE tem de existir no catálogo. Se alguém acrescentar um idioma a uma raça
# ou a um antecedente sem catalogá-lo, quebra aqui em vez de sumir da ficha.
RSpec.describe 'as fontes de idioma reconciliam com o catálogo' do
  before(:all) do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  before do
    Proficiency.of('language').destroy_all
    Proficiencies::LanguageReader.reset_cache!
    Rake::Task['dnd:seed_proficiency_languages'].reenable
    Rake::Task['dnd:seed_proficiency_languages'].invoke
  end

  after { Proficiencies::LanguageReader.reset_cache! }

  def resolve(v) = Proficiency.resolve(v, category: 'language')

  it 'race_rules.yml — todo idioma fixo e toda opção estão catalogados' do
    yaml = YAML.load_file(Rails.root.join('config', 'race_rules.yml'))
    vistos = []
    anda = lambda do |n|
      case n
      when Hash
        if n['languages'].is_a?(Hash)
          vistos.concat(Array(n['languages']['always']))
          vistos.concat(Array(n['languages']['choices']))
        end
        n.each_value { |v| anda.call(v) }
      when Array then n.each { |v| anda.call(v) }
      end
    end
    anda.call(yaml)

    expect(vistos).not_to be_empty, 'o extrator não achou idioma nenhum — mudou a forma do YAML?'
    expect(vistos.uniq.reject { |v| resolve(v) }).to eq([])
  end

  it 'background_rules.rb — toda opção oferecida está catalogada' do
    # ⚠️ Lê a CONSTANTE, não a tabela. `Background` é semeada A PARTIR daqui, e
    # o banco de teste não a semeia — a primeira versão deste teste passava por
    # vacuidade sobre uma tabela vazia. O guarda `not_to be_empty` abaixo é o
    # que denunciou isso, e fica.
    ofertas = BackgroundRules::RULES.values.flat_map do |bg|
      bloco = bg[:languages] || bg['languages']
      bloco.is_a?(Hash) ? Array(bloco[:choices] || bloco['choices']) : []
    end
    expect(ofertas).not_to be_empty
    expect(ofertas.uniq.reject { |v| resolve(v) }).to eq([])
  end

  it '⚠️ o guarda PEGA um idioma não catalogado — senão é teatro' do
    # Um teste de reconciliação que passa com qualquer entrada não reconcilia
    # nada. Aqui está a prova de que ele reprova o caso que existe para prender.
    expect(resolve('Klingon')).to be_nil
  end

  it 'o catálogo do FRONT (que bate com o livro) resolve inteiro' do
    # As duas tabelas do PHB pt-BR pg. 123, mais dialetos e monstro. Se o front
    # passar a consumir o endpoint, é esta lista que ele recebe.
    do_front = %w[
      Anão Comum Élfico Gigante Gnômico Goblin Halfling Orc
      Abissal Celestial Dracônico Infernal Primordial Silvestre Subcomum
      Aquan Auran Ignan Terran Esfinge
    ] + ['Dialeto Subterrâneo', 'Língua do Caos']
    expect(do_front.reject { |v| resolve(v) }).to eq([])
  end
end
