# frozen_string_literal: true

require 'rails_helper'

# Marcar na agenda é idempotente pela chave (L0.4): é o que deixa reprocessar sem criar eventos em dobro.
RSpec.describe Mundo::Agenda::Marca do
  let(:mundo) { create(:mundo) }

  it 'marca uma vez por chave e devolve o que já existe, como está' do
    primeiro = described_class.call(mundo, minuto: 100, tipo: 'sino', chave: 'x', dados: { 'a_cada' => 60 })
    de_novo = described_class.call(mundo, minuto: 999, tipo: 'sino', chave: 'x')

    expect(de_novo.id).to eq(primeiro.id)
    expect(de_novo.minuto).to eq(100)
    expect(de_novo.dados).to eq('a_cada' => 60)
    expect(mundo.eventos.count).to eq(1)
  end

  it 'a mesma chave em outro mundo é outro evento' do
    described_class.call(mundo, minuto: 100, tipo: 'sino', chave: 'x')
    described_class.call(create(:mundo), minuto: 100, tipo: 'sino', chave: 'x')

    expect(Mundo::Evento.where(chave: 'x').count).to eq(2)
  end

  it 'recusa um minuto que não seja inteiro e não negativo' do
    expect { described_class.call(mundo, minuto: -1, tipo: 'sino', chave: 'a') }.to raise_error(ArgumentError)
    expect { described_class.call(mundo, minuto: 1.5, tipo: 'sino', chave: 'b') }.to raise_error(ArgumentError)
  end

  it 'some com o mundo' do
    described_class.call(mundo, minuto: 100, tipo: 'sino', chave: 'x')

    expect { mundo.destroy }.to change(Mundo::Evento, :count).by(-1)
  end
end
