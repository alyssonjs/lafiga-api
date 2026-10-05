# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# A semeadura do MODELO de cada armadura e escudo no banco (05/10). O risco não é a rake falhar: é ela gravar no DRY
# RUN, passar por cima do modelo que o Mestre escolheu no catálogo, ou adivinhar o modelo pelo NOME.
RSpec.describe 'lpc:modelos_do_catalogo' do
  before(:all) do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  def rodar(aplicar: false)
    Rake::Task['lpc:modelos_do_catalogo'].reenable
    ENV['APPLY'] = '1' if aplicar
    expect { Rake::Task['lpc:modelos_do_catalogo'].invoke }.to output(/SEM MODELO/).to_stdout
  ensure
    ENV.delete('APPLY')
  end

  def item!(idx, kind:, category: nil, name: nil, props: {})
    Item.where(api_index: idx).delete_all
    Item.create!(api_index: idx, name: name || idx.tr('-', ' ').capitalize, kind: kind, category: category, props: props)
  end

  it 'DRY RUN é o padrão — não grava nada' do
    couro = item!('leather', kind: 'armor', category: 'light', props: { 'ac_base' => 11 })
    rodar
    expect(couro.reload.props).to eq('ac_base' => 11)
  end

  it 'APPLY=1 grava pelo índice e pela categoria, mantém a escolha do Mestre e não adivinha pelo nome' do
    couro = item!('leather', kind: 'armor', category: 'light', props: { 'ac_base' => 11 })
    madeira = item!('escudo-de-madeira', kind: 'shield')
    brigantina = item!('brigantina-da-mesa', kind: 'armor', category: 'medium')
    escolhida = [{ 'parte' => 'lpc:torso_armour_legion', 'cor' => { 'metal' => 'gold' } }]
    placas = item!('plate', kind: 'armor', category: 'heavy', props: { 'lpc_pecas' => escolhida })
    sem = item!('cota-de-malha-roupa', kind: 'armor', name: 'Cota de malha + roupa')

    rodar(aplicar: true)

    expect(couro.reload.props).to eq('ac_base' => 11,
                                     'lpc_pecas' => [{ 'parte' => 'lpc:torso_armour_leather', 'cor' => { 'cloth' => 'leather', 'metal' => 'iron' } }])
    expect(madeira.reload.props['lpc_pecas']).to eq([{ 'parte' => 'lpc:shield_round', 'cor' => { 'cloth' => 'brown' } }])
    expect(brigantina.reload.props['lpc_pecas']).to eq([{ 'parte' => 'lpc:torso_chainmail', 'cor' => { 'metal' => 'iron' } }])
    expect(placas.reload.props['lpc_pecas']).to eq(escolhida)
    expect(sem.reload.props).to eq({})
  end
end

# O importador do catálogo (o deploy roda com LAFIGA_RAILS_AFTER_DEPLOY=1) reescreve o `props` inteiro do item do
# `equipment.yml`: ele semeia o modelo das armaduras do livro e NÃO apaga o modelo que o Mestre escolheu.
RSpec.describe 'equipment:import_items e o modelo LPC' do
  before(:all) do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  it 'semeia o modelo do yml e mantém o escolhido pelo Mestre' do
    escolhida = [{ 'parte' => 'lpc:torso_armour_legion', 'cor' => { 'metal' => 'gold' } }]
    Item.where(api_index: %w[leather plate]).delete_all
    Item.create!(api_index: 'plate', name: 'Placas', kind: 'armor', category: 'heavy', props: { 'lpc_pecas' => escolhida })

    Rake::Task['equipment:import_items'].reenable
    expect { Rake::Task['equipment:import_items'].invoke }.to output(/Imported\/updated items/).to_stdout

    expect(Item.find_by(api_index: 'plate').props['lpc_pecas']).to eq(escolhida)
    expect(Item.find_by(api_index: 'leather').props['lpc_pecas'])
      .to eq([{ 'parte' => 'lpc:torso_armour_leather', 'cor' => { 'cloth' => 'leather', 'metal' => 'iron' } }])
    expect(Item.find_by(api_index: 'shield').props['lpc_pecas']).to eq([{ 'parte' => 'escudo' }])
  end
end
