# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# A rake que declara a capacidade de MOEDAS da Algibeira. O risco não é ela
# falhar: é SOBRESCREVER o que o mestre editou no catálogo (a capacidade é
# editável) ou deixar de completar a Algibeira que já existe sem a chave.
RSpec.describe 'dnd:seed_coin_containers' do
  before(:all) do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  def rodar
    Rake::Task['dnd:seed_coin_containers'].reenable
    expect { Rake::Task['dnd:seed_coin_containers'].invoke }.to output(/seed_coin_containers/).to_stdout
  end

  before { Item.where(api_index: 'algibeira').delete_all }

  it 'completa a Algibeira que existe sem a chave, preservando o resto das props' do
    item = Item.create!(api_index: 'algibeira', name: 'Algibeira', kind: 'gear', props: { 'card_icon_id' => 'x' })

    rodar

    expect(item.reload.props).to eq('card_icon_id' => 'x', 'coin_capacity' => 300)
  end

  it '⚠️ NÃO sobrescreve a capacidade que o mestre editou' do
    item = Item.create!(api_index: 'algibeira', name: 'Algibeira', kind: 'gear', props: { 'coin_capacity' => 120 })

    rodar

    expect(item.reload.props['coin_capacity']).to eq(120)
  end

  it 'cria a Algibeira quando o catálogo não a tem' do
    rodar

    expect(Item.find_by(api_index: 'algibeira')&.props).to include('coin_capacity' => 300)
  end
end
