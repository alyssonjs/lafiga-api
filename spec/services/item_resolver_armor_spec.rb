# frozen_string_literal: true

require 'rails_helper'

# Nome de armadura → `api_index` CANÔNICO.
#
# O bug que isto guarda: `ARMOR_PT_SLUGS` apontava para slugs em PORTUGUÊS
# (`half-plate` => `meia-armadura`) que não são a convenção do catálogo — as 12
# armaduras vivem com slug em INGLÊS. `create_item!` então criava uma CASCA
# VAZIA (sem `ac_base`/`dex_cap`) em vez de achar a armadura real, e quem a
# vestia ficava SEM CA de armadura.
RSpec.describe ItemResolver, '— armadura resolve para o slug canônico' do
  def resolve(nome)
    described_class.new.resolve(name: nome, category: 'Armaduras & Escudos')
  end

  before do
    # Catálogo real (slug em inglês, com as props de CA).
    Item.find_or_create_by!(api_index: 'half-plate') do |i|
      i.name = 'Meia-Armadura'; i.kind = 'armor'; i.category = 'medium'
      i.props = { 'ac_base' => 15, 'dex_cap' => 2 }
    end
    Item.find_or_create_by!(api_index: 'studded-leather') do |i|
      i.name = 'Couro Batido'; i.kind = 'armor'; i.category = 'light'
      i.props = { 'ac_base' => 12 }
    end
  end

  it '⚠️ o nome em PT acha a armadura REAL — não cria casca com slug PT' do
    # Era aqui que nascia `meia-armadura` sem `ac_base`.
    item = resolve('Meia-Armadura')
    expect(item.api_index).to eq('half-plate')
    expect(item.props['ac_base']).to eq(15)
    expect(Item.find_by(api_index: 'meia-armadura')).to be_nil
  end

  it 'o nome em INGLÊS cai no mesmo item', :aggregate_failures do
    expect(resolve('Half Plate').api_index).to eq('half-plate')
    expect(resolve('Studded Leather').api_index).to eq('studded-leather')
  end

  it 'as grafias ANTIGAS da base também convergem (leitor tolerante)' do
    # Nomes que já estavam gravados antes do alinhamento com o PHB.
    expect(resolve('Meia Armadura de Placas').api_index).to eq('half-plate')
    expect(resolve('Couro Reforçado').api_index).to eq('studded-leather')
  end

  it 'não inventa item para armadura que o catálogo não tem' do
    # Homebrew segue criando o próprio — o mapa não pode engolir tudo.
    item = resolve('Armadura de Casco de Tartaruga')
    expect(item.api_index).to eq('armadura-de-casco-de-tartaruga')
  end
end
