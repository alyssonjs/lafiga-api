# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# Quem CONCEDE cada proficiência — o índice reverso.
#
# ⚠️ É REGISTRO, não autoridade (decisão de produto). Quem de facto concede
# continua a ser `race_rules.yml`, `class_rules.rb`, `background_rules.rb` e a
# coluna do `Feat`. Marcar "Anão" aqui NÃO faz anão nenhum ganhar a
# proficiência — e é essa fronteira que estes testes prendem.
RSpec.describe ProficiencySource do
  let!(:lira) do
    Proficiency.create!(api_index: 'tool-lira', name: 'Lira', category: 'tool', sub_category: 'instrument')
  end

  it 'não repete a mesma fonte para a mesma proficiência' do
    described_class.create!(proficiency: lira, source_type: 'race', source_key: 'anao')
    dupe = described_class.new(proficiency: lira, source_type: 'race', source_key: 'anao')
    expect(dupe).not_to be_valid
  end

  it 'aceita a MESMA chave em tipos diferentes' do
    # "elfo" pode ser raça e sub-raça ao mesmo tempo noutro catálogo.
    described_class.create!(proficiency: lira, source_type: 'race', source_key: 'elfo')
    expect(described_class.new(proficiency: lira, source_type: 'sub_race', source_key: 'elfo')).to be_valid
  end

  it 'recusa tipo fora do vocabulário' do
    expect(described_class.new(proficiency: lira, source_type: 'inventado', source_key: 'x')).not_to be_valid
  end

  it 'o rótulo diz o TIPO por extenso' do
    src = described_class.create!(proficiency: lira, source_type: 'sub_klass',
                                  source_key: 'colegio-da-fortuna', source_name: 'Colégio da Fortuna')
    expect(src.label).to eq('Subclasse: Colégio da Fortuna')
  end

  it 'sem nome, o rótulo cai na chave — não fica vazio' do
    src = described_class.create!(proficiency: lira, source_type: 'race', source_key: 'anao')
    expect(src.label).to eq('Raça: anao')
  end
end

RSpec.describe 'derivação das fontes (rake)' do
  before(:all) do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  def derivar
    Rake::Task['dnd:seed_proficiency_sources'].reenable
    Rake::Task['dnd:seed_proficiency_sources'].invoke
  end

  it '⚠️ a associação MANUAL sobrevive a re-derivar' do
    # Sem isto, re-semear apagava o trabalho do mestre — e é o tipo de perda que
    # ninguém repara até fazer falta.
    p = Proficiency.create!(api_index: 'tool-x', name: 'X', category: 'tool', sub_category: 'artisan')
    ProficiencySource.create!(proficiency: p, source_type: 'sub_klass',
                              source_key: 'colegio-da-fortuna', origin: 'manual')
    expect { derivar }.not_to change { ProficiencySource.manual.count }
  end

  it '⚠️ poda a DERIVADA que já não vale, sem tocar na manual' do
    p = Proficiency.create!(api_index: 'tool-y', name: 'Y', category: 'tool', sub_category: 'artisan')
    ProficiencySource.create!(proficiency: p, source_type: 'race', source_key: 'inexistente', origin: 'derived')
    ProficiencySource.create!(proficiency: p, source_type: 'race', source_key: 'guardada', origin: 'manual')
    derivar
    expect(ProficiencySource.where(proficiency: p, source_key: 'inexistente')).to be_empty
    expect(ProficiencySource.where(proficiency: p, source_key: 'guardada')).to be_present
  end
end
