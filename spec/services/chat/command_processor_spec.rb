# frozen_string_literal: true

require 'rails_helper'

# Os comandos do chat da campanha rolam pelos dados do servidor (L0.6), com as chaves de sempre na resposta.
RSpec.describe Chat::CommandProcessor do
  it 'rola !d20+1 e devolve as chaves de antes' do
    r = described_class.call('!d20+1')

    expect(r).to include(type: 'roll', times: 1, sides: 20, mod: 1, expression: '1d20+1')
    expect(r[:rolls].size).to eq(1)
    expect(r[:total]).to eq(r[:rolls].first + 1)
    expect(r[:text]).to eq("Rolagem: 1d20 (#{r[:rolls].first}) + 1 = #{r[:total]}")
  end

  it 'entende a vantagem e os grupos somados' do
    expect(described_class.call('!2d20kh1+3')).to include(type: 'roll', expression: '2d20kh1+3')
    expect(described_class.call('!1d8+1d6')[:rolls].size).to eq(2)
  end

  it 'a ajuda, o desconhecido e o texto sem comando' do
    expect(described_class.call('!help')).to include(type: 'help')
    expect(described_class.call('!dança')).to include(type: 'unknown')
    expect(described_class.call('oi')).to be_nil
  end
end
