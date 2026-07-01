# frozen_string_literal: true

require 'rails_helper'

# R7 — RaceRules.ability_bonuses: fonte autoritativa server-side de
# race_bonuses_applied. Type-aware sobre o shape real de RaceRules.apply.
RSpec.describe 'RaceRules.ability_bonuses (R7)' do
  before { RaceRules.reload! }

  def bonuses(rid, sid, chosen = [])
    ab = RaceRules.apply(race_id: rid, subrace_id: sid, choices: {})[:ability]
    RaceRules.ability_bonuses(ab, chosen_abilities: chosen)
  end

  it 'fixed: Anão da Colina → CON+2, SAB+1' do
    expect(bonuses('dwarf', 'hill')).to eq('con' => 2, 'wis' => 1)
  end

  it 'fixed: Anão da Montanha → CON+2, FOR+2' do
    expect(bonuses('dwarf', 'mountain')).to eq('con' => 2, 'str' => 2)
  end

  it 'fixed: Draconato → FOR+2, CAR+1' do
    expect(bonuses('dragonborn', 'green')).to eq('str' => 2, 'cha' => 1)
  end

  it 'fixed: Humano Padrão → +1 em todos' do
    expect(bonuses('human', 'standard')).to eq(
      'str' => 1, 'dex' => 1, 'con' => 1, 'int' => 1, 'wis' => 1, 'cha' => 1
    )
  end

  it 'halfElf: +2 CAR fixo + 2 escolhidos (+1 cada)' do
    expect(bonuses('half_elf', nil, %w[dex wis])).to eq('cha' => 2, 'dex' => 1, 'wis' => 1)
  end

  it 'halfElf: aceita abreviações PT (DES/SAB)' do
    expect(bonuses('half_elf', nil, %w[DES SAB])).to eq('cha' => 2, 'dex' => 1, 'wis' => 1)
  end

  it 'variantHuman: SÓ os 2 escolhidos — NÃO herda o +1-em-tudo do Humano base' do
    expect(bonuses('human', 'variant', %w[dex con])).to eq('dex' => 1, 'con' => 1)
  end

  it 'respeita o count: ignora escolhas além do permitido' do
    # half-elf escolhe 2; uma 3ª opção é descartada
    expect(bonuses('half_elf', nil, %w[dex wis str])).to eq('cha' => 2, 'dex' => 1, 'wis' => 1)
  end

  it 'shape inválido/nil → {}' do
    expect(RaceRules.ability_bonuses(nil)).to eq({})
    expect(RaceRules.ability_bonuses({})).to eq({})
  end
end
