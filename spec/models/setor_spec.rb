# frozen_string_literal: true

require 'rails_helper'

# O setor (L1.1; plano B3 e I6): um território da campanha, com o estado, o território (a CD do acampamento) e as duas
# pressões, cada uma de 0 a 100.
RSpec.describe Setor do
  let(:campanha) { Campanhas::Inicia.call(create(:mundo), regiao: 'argoba') }

  def setor(**atributos)
    campanha.setores.build(
      { chave: 'ruinas', nome: 'Ruínas', tipo: 'selvagem', bioma: 'floresta', estado: 'perdido', territorio: 'comum',
        pressao_selvagem: 0, influencia: 0, ordem: 99 }.merge(atributos),
    )
  end

  it 'aceita um setor completo' do
    expect(setor).to be_valid
  end

  it 'recusa estado, tipo, território e bioma fora das listas' do
    expect(setor(estado: 'neutro')).not_to be_valid
    expect(setor(tipo: 'castelo')).not_to be_valid
    expect(setor(territorio: 'sagrado')).not_to be_valid
    expect(setor(bioma: 'selva')).not_to be_valid
  end

  it 'as pressões são inteiros de 0 a 100' do
    expect(setor(pressao_selvagem: 101)).not_to be_valid
    expect(setor(influencia: -1)).not_to be_valid
    expect(setor(influencia: 12.5)).not_to be_valid
    expect(setor(pressao_selvagem: 100, influencia: 0)).to be_valid
  end

  it 'a chave e a ordem não se repetem na mesma campanha, mas sim em outra' do
    expect(setor(chave: 'floresta')).not_to be_valid
    expect(setor(ordem: 1)).not_to be_valid

    outra = Campanhas::Inicia.call(create(:mundo), regiao: 'argoba')
    expect(outra.setores.find_by(chave: 'floresta')).to be_present
  end

  it 'a CD do acampamento vem do território, pela ficha da região' do
    expect(campanha.setores.find_by(chave: 'floresta').cd_acampamento).to eq(10)
    expect(campanha.setores.find_by(chave: 'posto').cd_acampamento).to eq(15)
    expect(campanha.setores.find_by(chave: 'primeiro-distrito').cd_acampamento).to eq(18)
  end
end
