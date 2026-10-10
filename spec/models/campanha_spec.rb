# frozen_string_literal: true

require 'rails_helper'

# A campanha regional (L1.1; plano B3, I1 e I5): a de um mundo numa região, com a ameaça e a etapa do arco.
RSpec.describe Campanha do
  let(:mundo) { create(:mundo) }
  let(:campanha) { Campanhas::Inicia.call(mundo, regiao: 'argoba') }

  it 'a chave é única no mundo' do
    copia = described_class.new(campanha.attributes.except('id', 'created_at', 'updated_at'))

    expect(copia).not_to be_valid
    expect(copia.errors.keys).to include(:chave)
  end

  it 'a etapa é uma das etapas do arco na ficha' do
    expect(campanha).to be_valid

    campanha.etapa = 'cidade'
    expect(campanha).to be_valid

    campanha.etapa = 'imperio'
    expect(campanha).not_to be_valid
    expect(campanha.errors[:etapa]).to be_present
  end

  it 'os setores vêm na ordem da corrente' do
    expect(campanha.setores.reload.map(&:chave).first(3)).to eq(%w[assentamento floresta buzios])
  end

  it 'apagar o mundo leva a campanha e os setores' do
    campanha
    mundo.destroy!

    expect(described_class.count).to eq(0)
    expect(Setor.count).to eq(0)
  end
end
