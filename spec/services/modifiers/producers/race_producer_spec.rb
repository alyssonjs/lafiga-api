# frozen_string_literal: true

require 'rails_helper'

# R2 — RaceProducer: traduz os `grants` dos trait_definitions de
# config/race_rules.yml em Modifiers de resistência/imunidade/vantagem,
# no mesmo canal que SubklassProducer/EquippedItemProducer.
RSpec.describe Modifiers::Producers::RaceProducer, type: :service do
  let(:user) do
    User.create!(
      email: "raceprod_#{SecureRandom.hex(4)}@ex.com",
      username: "rp#{SecureRandom.hex(4)}",
      password: 'password1', password_confirmation: 'password1',
      role_id: Role.find_or_create_by!(name: 'player').id,
    )
  end

  before { RaceRules.reload! }

  # Sheet tem 1:1 com Character — cada ficha precisa do seu próprio personagem.
  def new_character
    Character.create!(user: user, name: "RP #{SecureRandom.hex(4)}", background: 'Sage')
  end

  def race(api_index, name)
    Race.find_or_create_by!(api_index: api_index) { |r| r.name = name }
  end

  def subrace(race, api_index, name)
    SubRace.find_or_create_by!(race_id: race.id, api_index: api_index) { |s| s.name = name }
  end

  def make_sheet(race:, sub_race: nil)
    Sheet.create!(
      character: new_character, race: race, sub_race: sub_race,
      str: 10, dex: 14, con: 12, int: 10, wis: 12, cha: 10,
      hp_max: 10, hp_current: 10, current_level: 1,
    )
  end

  def grants_of(target_prefix, mods)
    mods.select { |m| m.target.to_s.start_with?(target_prefix) && m.op == :grant }
        .map(&:value).flatten.compact.uniq
  end

  it 'concede resistência a veneno e vantagem em save vs veneno (Anão)' do
    r = race('dwarf', 'Anão')
    sheet = make_sheet(race: r, sub_race: subrace(r, 'hill', 'Anão da Colina'))
    mods = described_class.new(sheet).produce

    expect(grants_of('resistance', mods)).to include('veneno')
    expect(grants_of('advantage.save', mods)).to include('Veneno')
    expect(mods.all? { |m| m.source_kind == :race }).to be(true)
  end

  it 'interpola <damage> da sub-raça para a resistência da ancestralidade dracônica' do
    r = race('dragonborn', 'Draconato')
    green = make_sheet(race: r, sub_race: subrace(r, 'green', 'Verde (Veneno)'))
    red   = make_sheet(race: r, sub_race: subrace(r, 'red', 'Vermelho (Fogo)'))

    expect(grants_of('resistance', described_class.new(green).produce)).to eq(['Veneno'])
    expect(grants_of('resistance', described_class.new(red).produce)).to eq(['Fogo'])
  end

  it 'concede imunidade à condição (sono mágico) e vantagem vs Enfeitiçado (Ancestralidade Feérica)' do
    r = race('elf', 'Elfo')
    sheet = make_sheet(race: r, sub_race: subrace(r, 'wood', 'Elfo da Floresta'))
    mods = described_class.new(sheet).produce

    expect(grants_of('condition_immunity', mods)).to include('Sono mágico')
    expect(grants_of('advantage.save', mods)).to include('Enfeitiçado')
  end

  it 'acumula Bravura (brave) + Resiliência (stout) no Halfling Robusto' do
    r = race('halfling', 'Halfling')
    sheet = make_sheet(race: r, sub_race: subrace(r, 'stout', 'Robusto'))
    mods = described_class.new(sheet).produce

    expect(grants_of('resistance', mods)).to include('veneno')
    expect(grants_of('advantage.save', mods)).to include('Amedrontado', 'Veneno')
  end

  it 'concede resistência de legado a fogo (Tiefling Infernal)' do
    r = race('tiefling', 'Tiefling')
    sheet = make_sheet(race: r, sub_race: subrace(r, 'infernal', 'Infernal'))
    expect(grants_of('resistance', described_class.new(sheet).produce)).to include('fogo')
  end

  it 'não concede nada para raça sem grants raciais (Meio-Orc base)' do
    sheet = make_sheet(race: race('half_orc', 'Meio-Orc'))
    mods = described_class.new(sheet).produce
    expect(grants_of('resistance', mods)).to be_empty
    expect(grants_of('advantage.save', mods)).to be_empty
  end

  it 'devolve [] e não levanta erro quando a ficha não tem raça' do
    sheet = Sheet.new(character: new_character, str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10, hp_max: 8, hp_current: 8, current_level: 1)
    expect(described_class.new(sheet).produce).to eq([])
  end
end
