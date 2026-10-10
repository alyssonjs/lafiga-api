# frozen_string_literal: true

require 'rails_helper'

# A região (L1.1; plano B3): a linha no banco é a identidade (para as chaves estrangeiras: a campanha, e depois a vila e
# o mapa); o resto mora na ficha yml.
RSpec.describe Regiao do
  it 'sincroniza a linha pela ficha, sem duplicar' do
    regiao = described_class.sincroniza!('argoba')

    expect(regiao).to have_attributes(chave: 'argoba', nome: 'Argoba', reino: 'zandria')
    expect(described_class.sincroniza!('argoba')).to eq(regiao)
    expect(described_class.count).to eq(1)
  end

  it 'a ficha manda: o nome mudado à mão volta ao da ficha' do
    regiao = described_class.sincroniza!('argoba')
    regiao.update!(nome: 'Outro nome')

    expect(described_class.sincroniza!('argoba').nome).to eq('Argoba')
  end

  it 'lê a própria ficha' do
    expect(described_class.sincroniza!('argoba').ficha['reino']).to eq('zandria')
  end

  it 'a chave é única' do
    described_class.create!(chave: 'argoba', nome: 'Argoba', reino: 'zandria')

    expect(described_class.new(chave: 'argoba', nome: 'B', reino: 'zandria')).not_to be_valid
  end

  it 'pede nome e reino' do
    regiao = described_class.new(chave: 'x')

    expect(regiao).not_to be_valid
    expect(regiao.errors.keys).to include(:nome, :reino)
  end
end
