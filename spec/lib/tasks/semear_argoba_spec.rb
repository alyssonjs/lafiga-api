# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# O seed de dev de Argoba (L1.1): dá a um grupo o relógio (se ainda não tem) e a campanha de Argoba.
RSpec.describe 'mundo:semear_argoba' do
  before(:all) do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  let(:mestre) { create(:user) }
  let(:group) { create(:group, dm_user: mestre) }

  def rodar(group_id)
    Rake::Task['mundo:semear_argoba'].reenable
    saida = StringIO.new
    antes = $stdout
    $stdout = saida
    Rake::Task['mundo:semear_argoba'].invoke(group_id.to_s)
    saida.string
  ensure
    $stdout = antes
  end

  it 'dá ao grupo sem relógio o mundo e a campanha de Argoba' do
    saida = rodar(group.id)

    mundo = group.reload.mundo
    expect(mundo).to have_attributes(minuto_na_epoca: 720, fator: 40)
    expect(mundo.campanhas.map(&:chave)).to eq(['retomada-de-argoba'])
    expect(saida).to include("grupo #{group.id}", 'A Retomada de Argoba', '7 setores')
  end

  it 'rodar de novo não duplica nada e mantém o relógio' do
    rodar(group.id)
    epoca = group.reload.mundo.epoca_em

    rodar(group.id)

    expect(group.reload.mundo.epoca_em).to eq(epoca)
    expect([Mundo.count, Campanha.count, Setor.count]).to eq([1, 1, 7])
  end

  it 'aponta a fauna da ficha que não está no banco de monstros' do
    Monster.create!(slug: 'open5e-wolf', name: 'Lobo')

    saida = rodar(group.id)

    expect(saida).to include('fauna sem ficha no banco', 'open5e-owlbear')
    expect(saida).not_to match(/sem ficha no banco:.*open5e-wolf/)
  end

  it 'dá ao assentamento a casca do mapa em blocos (L1.2), uma vez só' do
    saida = rodar(group.id)
    rodar(group.id)

    campanha = group.reload.mundo.campanhas.first
    mapas = BattleMap.where(setor_id: campanha.setores.find_by!(chave: 'assentamento').id)
    expect(mapas.count).to eq(1)
    expect(mapas.first).to have_attributes(
      map_kind: 'vila', armazenamento: 'blocos', width: 200, height: 200, cells: [], group_id: group.id, user_id: mestre.id,
    )
    expect(saida).to include("mapa do assentamento: battle_map #{mapas.first.id} (200×200, 0 blocos)")
  end

  it 'grupo sem Mestre não ganha mapa: o dono do mapa é o Mestre do grupo' do
    sem_mestre = create(:group)

    expect { rodar(sem_mestre.id) }.to raise_error(ArgumentError, /não tem Mestre/)
  end

  it 'grupo que não existe é erro' do
    expect { rodar(0) }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
