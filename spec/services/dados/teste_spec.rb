# frozen_string_literal: true

require 'rails_helper'

# O teste de d20 (L0.6; Livro do Jogador, cap. 7). Os dados mudam a cada máquina (o segredo vem do secret_key_base),
# então as expectativas são sobre as contas, não sobre números sorteados.
RSpec.describe Dados::Teste do
  def natural(r)
    r.detalhe['natural']
  end

  it 'soma o atributo, a proficiência e os situacionais ao d20' do
    r = described_class.call(chave: 't:1', atributo: 3, proficiencia: 2, proficiente: true, situacional: 1)

    expect(r.expressao).to eq('1d20+6')
    expect(r.total).to eq(natural(r) + 6)
    expect(r.detalhe).to include('atributo' => 3, 'proficiencia' => 2, 'especialista' => false, 'situacional' => 1)
  end

  it 'a especialização dobra a proficiência; sem proficiência, nem ela nem a especialização contam' do
    especialista = described_class.call(chave: 't:2', atributo: 1, proficiencia: 3, proficiente: true, especialista: true)
    leigo = described_class.call(chave: 't:3', atributo: 1, proficiencia: 3, proficiente: false, especialista: true)

    expect(especialista.detalhe).to include('proficiencia' => 6, 'especialista' => true)
    expect(especialista.total).to eq(natural(especialista) + 7)
    expect(leigo.detalhe).to include('proficiencia' => 0, 'especialista' => false)
    expect(leigo.total).to eq(natural(leigo) + 1)
  end

  it 'com vantagem fica o maior d20, com desvantagem o menor' do
    10.times do |i|
      vantagem = described_class.call(chave: "t:v:#{i}", vantagem: :vantagem, fonte: :hmac)
      desvantagem = described_class.call(chave: "t:d:#{i}", vantagem: 'desvantagem', fonte: :hmac)

      expect(vantagem.expressao).to eq('2d20kh1')
      expect(natural(vantagem)).to eq(vantagem.dados.first['rolagens'].max)
      expect(natural(desvantagem)).to eq(desvantagem.dados.first['rolagens'].min)
    end
  end

  it 'contra a CD, diz se passou e por quanto' do
    r = described_class.call(chave: 't:4', atributo: 2, cd: 12)

    expect(r.detalhe['sucesso']).to eq(r.total >= 12)
    expect(r.detalhe['margem']).to eq(r.total - 12)
  end

  it 'na fonte hmac, a mesma chave dá o mesmo teste' do
    a = described_class.call(chave: 't:5', atributo: 4, fonte: :hmac)
    expect(described_class.call(chave: 't:5', atributo: 4, fonte: :hmac).id).to eq(a.id)
    expect(Dados::Verifica.call(a).ok).to be(true)
  end

  it 'recusa uma vantagem que não existe' do
    expect { described_class.call(chave: 't:6', vantagem: 'sorte') }.to raise_error(ArgumentError)
  end
end
