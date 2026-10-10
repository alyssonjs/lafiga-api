# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mundo, type: :model do
  let(:mundo) { create(:mundo, epoca_em: Time.utc(2026, 10, 9), minuto_na_epoca: 0, fator: 40) }

  it 'é um por grupo' do
    expect(mundo.group.reload.mundo).to eq(mundo)
    expect(build(:mundo, group_id: mundo.group_id)).not_to be_valid
  end

  it 'pede fator inteiro positivo e minuto não negativo' do
    expect(build(:mundo, fator: 0)).not_to be_valid
    expect(build(:mundo, minuto_na_epoca: -1)).not_to be_valid
  end

  it 'diz o momento em um agora (36 min reais = um dia de jogo)' do
    expect(mundo.momento_em(Time.utc(2026, 10, 9, 0, 36))).to include(dia: 1, hora: 0, criador: "M'avi", periodo: 'noite')
  end

  it 'reancora sem salto e guarda a época com milissegundos no banco' do
    agora = Time.utc(2026, 10, 9, 0, 36, Rational(750, 1000))
    mundo.reancora!(agora: agora, fator: 20)
    mundo.reload

    expect(mundo.fator).to eq(20)
    expect(mundo.minuto_na_epoca).to eq(1440)
    expect(mundo.epoca_em.utc.iso8601(3)).to eq('2026-10-09T00:35:59.250Z')
    expect(mundo.minuto_em(agora)).to eq(1440)
    expect(mundo.minuto_em(Time.utc(2026, 10, 9, 0, 36, Rational(2250, 1000)))).to eq(1441)
  end

  it 'avança de propósito (o dev), guardando a fração do minuto' do
    agora = Time.utc(2026, 10, 9, 0, 36, Rational(750, 1000))
    mundo.avanca!(agora: agora, minutos: 8 * 60)

    expect(mundo.reload.minuto_em(agora)).to eq(1440 + 480)
    expect(mundo.minuto_em(agora + Rational(750, 1000))).to eq(1440 + 481)
  end

  it 'mostra a âncora para a API com milissegundos' do
    expect(mundo.para_api).to include(epoca_em: '2026-10-09T00:00:00.000Z', minuto_na_epoca: 0, fator: 40, pausado_desde: nil)
  end

  it 'pausa e despausa pelo grupo, e some com ele' do
    mundo.reancora!(agora: Time.utc(2026, 10, 9, 0, 36), pausar: true)
    expect(mundo.reload.minuto_em(Time.utc(2026, 10, 10))).to eq(1440)

    mundo.reancora!(agora: Time.utc(2026, 10, 10), pausar: false)
    expect(mundo.reload.minuto_em(Time.utc(2026, 10, 10, 0, 0, Rational(1500, 1000)))).to eq(1441)

    expect { mundo.group.destroy }.to change(described_class, :count).by(-1)
  end
end
