# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# FASE 0 do catálogo — IDIOMAS.
#
# O que este guarda prende não é "existem 27 linhas": é que o catálogo continua
# sendo a UNIÃO das fontes que já existiam. Escrever uma lista nova e "limpa" é
# exatamente o que criou as quatro grafias de "Veículos terrestres"; cortar um
# valor que parece errado órfã personagem real.
RSpec.describe 'catálogo de idiomas (fase 0)' do
  before(:all) do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  before do
    Proficiency.of('language').destroy_all
    Rake::Task['dnd:seed_proficiency_languages'].reenable
    Rake::Task['dnd:seed_proficiency_languages'].invoke
  end

  let(:por_sub) { Proficiency.of('language').group(:sub_category).count }

  it 'traz as duas tabelas do Livro do Jogador (pg. 123), completas' do
    padrao = %w[Anão Comum Élfico Gigante Gnômico Goblin Halfling Orc]
    exoticos = ['Abissal', 'Celestial', 'Dialeto Subterrâneo', 'Dracônico',
                'Infernal', 'Primordial', 'Silvestre', 'Subcomum']
    expect(Proficiency.of('language').where(sub_category: 'standard').pluck(:name).sort).to eq(padrao.sort)
    # +1: "Anão das Profundezas" entra como exótico marcado homebrew (ver abaixo)
    expect(Proficiency.of('language').where(sub_category: 'exotic').pluck(:name)).to include(*exoticos)
  end

  it 'os quatro dialetos sabem que são do Primordial — e ele, deles' do
    # O livro é explícito: quem fala um dialeto entende os outros. Perder essa
    # relação faria a ficha dizer "fala Ignan" sugerindo que Terran é inacessível.
    %w[Aquan Auran Ignan Terran].each do |d|
      p = Proficiency.resolve(d, category: 'language')
      expect(p.sub_category).to eq('primordial_dialect')
      expect(p.metadata['dialect_of']).to eq('lang-primordial')
    end
    expect(Proficiency.resolve('Primordial').metadata['dialects']).to match_array(
      %w[lang-aquan lang-auran lang-ignan lang-terran],
    )
  end

  it '⚠️ os secretos de classe estão no catálogo mas NÃO são escolhíveis' do
    # Druídico e Gíria de Ladrão vêm com a classe no nível 1. Estão aqui para
    # poderem ser exibidos e auditados; `grantable: false` é o que impede um
    # mago de os escolher numa lista de opções.
    %w[Druídico].each do |n|
      expect(Proficiency.resolve(n).metadata['grantable']).to be(false)
    end
    expect(Proficiency.resolve("Thieves' Cant").name).to eq('Gíria de Ladrão')
  end

  it 'os raciais de suplemento sobrevivem — têm personagem real' do
    # Aarakocra (2 fichas) e Minotauro (3) não estão no livro. Cortá-los para
    # "limpar" o catálogo deixaria cinco fichas órfãs.
    expect(por_sub['racial']).to eq(2)
    expect(Proficiency.resolve('Aarakocra')).to be_present
    expect(Proficiency.resolve('Minotauro')).to be_present
  end

  it '⚠️ "Anão das Profundezas" fica marcado, não fundido por palpite' do
    # Não está em nenhuma tabela do PHB pt-BR e chegou por `background_rules.rb`.
    # Parece-se com "Dialeto Subterrâneo", mas fundir por semelhança é como se
    # criam apelidos errados — e 6 antecedentes ainda o oferecem.
    p = Proficiency.resolve('Anão das Profundezas')
    expect(p.source).to eq('homebrew')
    expect(p).not_to eq(Proficiency.resolve('Dialeto Subterrâneo'))
  end

  it 'é idempotente — a segunda semeadura não cria nada' do
    antes = [Proficiency.count, ProficiencyAlias.count]
    Rake::Task['dnd:seed_proficiency_languages'].reenable
    Rake::Task['dnd:seed_proficiency_languages'].invoke
    expect([Proficiency.count, ProficiencyAlias.count]).to eq(antes)
  end

  describe 'cobre o que já está GRAVADO' do
    it '⚠️ todo idioma das fontes originais resolve — 0 órfãs' do
      # Esta é a razão de ser da fase 0. As fontes: o catálogo do front (bate
      # com o livro), `race_rules.yml`, `background_rules.rb` e o que está em
      # `sheets.race_summary.languages`.
      das_fontes = %w[
        Comum Anão Élfico Gigante Gnômico Goblin Halfling Orc
        Abissal Celestial Dracônico Infernal Primordial Silvestre Subcomum
        Aquan Auran Ignan Terran Esfinge Aarakocra Minotauro
      ] + ['Dialeto Subterrâneo', 'Língua do Caos', 'Anão das Profundezas']

      orfas = das_fontes.reject { |v| Proficiency.resolve(v, category: 'language') }
      expect(orfas).to eq([])
    end
  end
end
