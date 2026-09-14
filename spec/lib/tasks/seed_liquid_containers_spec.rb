# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# Recipientes de LÍQUIDO do PHB (tabela "Capacidade de Recipientes"). O risco da
# rake é passar por cima de um teto que o mestre ajustou.
RSpec.describe 'dnd:seed_liquid_containers' do
  before(:all) do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  def rodar
    Rake::Task['dnd:seed_liquid_containers'].reenable
    expect { Rake::Task['dnd:seed_liquid_containers'].invoke }.to output(/seed_liquid_containers/).to_stdout
  end

  def item!(idx, props = {})
    Item.where(api_index: idx).delete_all
    Item.create!(api_index: idx, name: idx.capitalize, kind: 'gear', category: 'container', props: props)
  end

  it 'declara a capacidade do livro nos recipientes do catálogo, sem mexer no resto' do
    barril = item!('barril', 'cost_cp' => 200)
    frasco = item!('frasco')

    rodar

    expect(barril.reload.props).to eq('cost_cp' => 200, 'liquid_capacity_l' => 160)
    expect(frasco.reload.props['liquid_capacity_l']).to eq(0.12)
  end

  it '⚠️ não sobrescreve o teto que o mestre ajustou, e rodar de novo não muda nada' do
    balde = item!('balde', 'liquid_capacity_l' => 10)

    rodar
    rodar

    expect(balde.reload.props['liquid_capacity_l']).to eq(10)
  end

  it 'não cria item que o catálogo não tem' do
    Item.where(api_index: 'jarra').delete_all

    rodar

    expect(Item.find_by(api_index: 'jarra')).to be_nil
  end
end
