# frozen_string_literal: true

require 'rails_helper'

# Começar a campanha de uma região num mundo (L1.1): a região, a campanha e os setores, pela ficha. Rodar de novo não
# duplica e não desfaz o que mudou em jogo.
RSpec.describe Campanhas::Inicia do
  let(:mundo) { create(:mundo) }

  it 'cria a campanha de Argoba com os setores da ficha' do
    campanha = described_class.call(mundo, regiao: 'argoba')

    expect(campanha).to have_attributes(
      mundo: mundo, chave: 'retomada-de-argoba', nome: 'A Retomada de Argoba', ameaca: 'colonizador',
      etapa: 'assentamento',
    )
    expect(campanha.regiao).to have_attributes(chave: 'argoba', reino: 'zandria')
    expect(campanha.setores.map { |s| [s.ordem, s.chave, s.estado, s.pressao_selvagem, s.influencia] }).to eq(
      [
        [1, 'assentamento', 'recuperado', 20, 0],
        [2, 'floresta', 'disputado', 35, 10],
        [3, 'buzios', 'recuperado', 30, 15],
        [4, 'estrada', 'disputado', 40, 30],
        [5, 'posto', 'perdido', 45, 50],
        [6, 'periferia', 'perdido', 55, 70],
        [7, 'primeiro-distrito', 'perdido', 60, 85],
      ],
    )
  end

  it 'rodar de novo não duplica nada' do
    primeira = described_class.call(mundo, regiao: 'argoba')

    expect(described_class.call(mundo, regiao: 'argoba')).to eq(primeira)
    expect([Regiao.count, Campanha.count, Setor.count]).to eq([1, 1, 7])
  end

  it 'rodar de novo não desfaz o que mudou em jogo' do
    campanha = described_class.call(mundo, regiao: 'argoba')
    campanha.update!(etapa: 'postos')
    campanha.setores.find_by!(chave: 'floresta').update!(influencia: 64, estado: 'perdido')

    described_class.call(mundo, regiao: 'argoba')

    expect(campanha.reload.etapa).to eq('postos')
    expect(campanha.setores.find_by!(chave: 'floresta')).to have_attributes(influencia: 64, estado: 'perdido')
  end

  it 'o setor que a ficha ganhou depois entra na campanha que já existe' do
    campanha = described_class.call(mundo, regiao: 'argoba')
    campanha.setores.find_by!(chave: 'periferia').destroy!

    described_class.call(mundo, regiao: 'argoba')

    expect(campanha.setores.reload.find_by(chave: 'periferia')).to have_attributes(ordem: 6, influencia: 70)
  end

  it 'cada mundo tem a sua campanha; a região é uma só' do
    a = described_class.call(mundo, regiao: 'argoba')
    b = described_class.call(create(:mundo), regiao: 'argoba')

    expect(a).not_to eq(b)
    expect(a.regiao).to eq(b.regiao)
    expect(Setor.count).to eq(14)
  end

  it 'região sem ficha é erro, e nada fica gravado' do
    expect { described_class.call(mundo, regiao: 'atlantida') }.to raise_error(ArgumentError, /região sem ficha/)
    expect([Regiao.count, Campanha.count]).to eq([0, 0])
  end
end
