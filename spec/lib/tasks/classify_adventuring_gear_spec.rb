# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# Classificação do equipamento de aventura nas subcategorias. O risco não é a
# rake falhar: é ela gravar no DRY RUN, passar por cima de uma categoria que o
# mestre escolheu, ou deixar para trás a roupa que o editor de transporte
# transformou em veículo.
RSpec.describe 'dnd:classify_adventuring_gear' do
  before(:all) do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  def rodar(aplicar: false)
    Rake::Task['dnd:classify_adventuring_gear'].reenable
    ENV['APPLY'] = '1' if aplicar
    expect { Rake::Task['dnd:classify_adventuring_gear'].invoke }.to output(/classify_adventuring_gear/).to_stdout
  ensure
    ENV.delete('APPLY')
  end

  def item!(idx, category, props = {})
    Item.where(api_index: idx).delete_all
    Item.create!(api_index: idx, name: idx.tr('-', ' ').capitalize, kind: 'gear', category: category, props: props)
  end

  it 'DRY RUN é o padrão — não grava nada' do
    alg = item!('algibeira', 'equipment', 'coin_capacity' => 300)

    rodar

    expect(alg.reload.category).to eq('equipment')
  end

  it 'APPLY=1 põe cada item do livro na subcategoria, pelo api_index, sem mexer na regra' do
    alg = item!('algibeira', 'equipment', 'coin_capacity' => 300)
    orbe = item!('orbe-foco-arcano', 'equipment')
    lanterna = item!('lanterna-coberta', 'equipment')
    municao = item!('bolsa-de-municao', nil, 'equipment_slot' => 'quiver')

    rodar(aplicar: true)

    expect([alg, orbe, lanterna, municao].map { |i| i.reload.category })
      .to eq(%w[coin-pouch arcane-focus lighting ammo-container])
    expect(alg.props).to eq('coin_capacity' => 300)
    expect(municao.props).to eq('equipment_slot' => 'quiver')
  end

  it '⚠️ repara a roupa que o editor de transporte transformou em veículo terrestre' do
    roupa = item!('roupa-de-viajante', 'vehicle_land')

    rodar(aplicar: true)

    expect(roupa.reload.category).to eq('clothes')
    # Roupa não é peça de Vestuário (lá toda peça tem slot): nem peça, nem slot.
    expect(roupa.props).not_to have_key('wardrobe_piece')
    expect(roupa.props).not_to have_key('equip_slot')
  end

  it 'o manto vira peça de manto e ganha o slot' do
    manto = item!('manto', 'equipment')

    rodar(aplicar: true)

    expect(manto.reload.category).to eq('cloak')
    expect(manto.props).to include('equip_slot' => 'cloak', 'wardrobe_piece' => 'cloak')
  end

  it 'não sobrescreve um slot que o mestre já declarou no manto' do
    manto = item!('manto', 'equipment', 'equip_slot' => 'x-do-mestre')

    rodar(aplicar: true)

    expect(manto.reload.category).to eq('cloak')
    expect(manto.props).to include('equip_slot' => 'x-do-mestre')
  end

  it '⚠️ não passa por cima de categoria escolhida pelo mestre' do
    mochila = item!('mochila', 'bag', 'capacity_kg' => 15)

    rodar(aplicar: true)

    expect(mochila.reload.category).to eq('bag')
  end

  it 'item fora do mapa não é tocado, e rodar de novo não muda nada' do
    abaco = item!('abaco', 'equipment')
    alg = item!('algibeira', 'equipment')

    rodar(aplicar: true)
    rodar(aplicar: true)

    expect(abaco.reload.category).to eq('equipment')
    expect(alg.reload.category).to eq('coin-pouch')
  end
end
