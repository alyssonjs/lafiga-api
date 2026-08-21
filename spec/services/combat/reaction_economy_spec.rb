# frozen_string_literal: true

require 'rails_helper'

# Regra da mesa: a reação recarrega na VIRADA DA RODADA.
#
# Estas specs existem porque a regra foi reintroduzida ERRADA no servidor duas
# vezes seguidas (descoberta de reatores e respond do Acorde), cada uma com um
# sintoma diferente. Aqui ela tem uma casa só.
RSpec.describe Combat::ReactionEconomy do
  # Dublê leve: o módulo só lê `actions_used` e `turn_state`.
  Reator = Struct.new(:actions_used, :turn_state)

  def reator(usada:, carimbo: nil)
    Reator.new({ 'reaction' => usada }, carimbo.nil? ? {} : { 'reactionUsedRound' => carimbo })
  end

  it 'reação não usada está sempre disponível' do
    expect(described_class.available?(reator(usada: false), 5)).to be true
  end

  it '⚠️ carimbo de rodada PASSADA libera, mesmo com a flag crua presa em true' do
    # A flag só é limpa no turno DO REATOR: entre a virada e a vez dele ela mente.
    expect(described_class.available?(reator(usada: true, carimbo: 4), 5)).to be true
  end

  it 'carimbo da rodada ATUAL bloqueia' do
    expect(described_class.available?(reator(usada: true, carimbo: 5), 5)).to be false
  end

  it 'carimbo de rodada FUTURA bloqueia (relógio inconsistente não libera)' do
    expect(described_class.available?(reator(usada: true, carimbo: 6), 5)).to be false
  end

  it 'flag true SEM carimbo bloqueia — não dá para datar o uso' do
    expect(described_class.available?(reator(usada: true), 5)).to be false
  end

  it 'combatente ausente não impõe restrição' do
    expect(described_class.available?(nil, 5)).to be true
  end

  it 'aceita as formas truthy que o JSON traz' do
    ['true', 1, '1', true].each do |v|
      combatente = Reator.new({ 'reaction' => v }, { 'reactionUsedRound' => 5 })
      expect(described_class.available?(combatente, 5)).to be false
    end
  end
end
