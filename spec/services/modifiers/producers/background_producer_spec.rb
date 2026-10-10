# frozen_string_literal: true

require 'rails_helper'

# L0.9 — BackgroundProducer: o antecedente deixa de ser só texto. Os `grants:` da regra do antecedente (o catálogo, a
# linha de `backgrounds.rules` ou a variação) viram Modifiers, no molde do RaceProducer. O caso comum do Nível 1 é a
# vantagem SITUACIONAL, que sai num alvo próprio e o resumo da ficha publica.
RSpec.describe Modifiers::Producers::BackgroundProducer, type: :service do
  let(:user) { create(:user) }
  let(:raca) { Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' } }

  before { BackgroundRules.clear_cache! }
  after { BackgroundRules.clear_cache! }

  def antecedente!(api_index, rules, parent: nil)
    Background.create!(api_index: api_index, name: api_index.humanize, rules: rules, parent_api_index: parent)
  end

  def ficha(background_key)
    character = Character.create!(user: user, name: "BP #{SecureRandom.hex(3)}", background: 'x')
    Sheet.create!(character: character, race: raca, background_key: background_key,
                  str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10, hp_max: 10, hp_current: 10, current_level: 1)
  end

  let(:nobre) do
    {
      'name' => 'Nobre de Teste', 'skills' => %w[História Persuasão],
      'grants' => {
        'situacionais' => [{ 'pericia' => 'Persuasão', 'quando' => 'com a nobreza' }],
        'advantages' => { 'skills' => ['Intuição'] },
        'defenses' => { 'resistance' => ['psíquico'] },
      },
    }
  end

  it 'sem antecedente, nada' do
    expect(described_class.new(ficha(nil)).produce).to eq([])
  end

  it 'o antecedente do catálogo ainda não tem grants: nada (a mecânica de cada um é decisão da mesa)' do
    expect(described_class.new(ficha('acolyte')).produce).to eq([])
  end

  it 'lê os grants da regra e gera os Modifiers com a fonte do antecedente' do
    antecedente!('nobre-l09', nobre)
    mods = described_class.new(ficha('nobre-l09')).produce

    expect(mods.map(&:source_kind).uniq).to eq([:background])
    situacional = mods.find { |m| m.target == 'situational_advantage.skill' }
    expect(situacional.value).to eq('pericia' => 'Persuasão', 'quando' => 'com a nobreza', 'fonte' => 'Nobre de Teste')
    expect(situacional.op).to eq(:grant)
    expect(mods.find { |m| m.target == 'advantage.skill' }&.value).to eq('Intuição')
    expect(mods.find { |m| m.target == 'resistance.psíquico' }&.value).to eq('psíquico')
  end

  it 'a variação herda os grants do pai (e troca a lista que redefine)' do
    antecedente!('nobre-l09', nobre)
    antecedente!('cavaleiro-l09', { 'grants' => { 'situacionais' => [{ 'pericia' => 'Atletismo', 'quando' => 'em torneios' }] } },
                 parent: 'nobre-l09')
    mods = described_class.new(ficha('cavaleiro-l09')).produce

    expect(mods.select { |m| m.target == 'situational_advantage.skill' }.map { |m| m.value['pericia'] }).to eq(['Atletismo'])
    expect(mods.find { |m| m.target == 'advantage.skill' }&.value).to eq('Intuição')
  end

  it 'o resolvedor roda o antecedente, e o resumo da ficha publica a vantagem situacional à parte' do
    antecedente!('nobre-l09', nobre)
    sheet = ficha('nobre-l09')

    bag = Modifiers::ModifierResolver.new(sheet).call
    expect(bag.granted('advantage.skill')).to include('Intuição')
    expect(bag.granted('advantage.skill')).not_to include(a_string_including('nobreza'))

    resumo = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false).result
    expect(resumo.dig(:modifiers, :situational_advantages)).to eq(
      [{ 'pericia' => 'Persuasão', 'quando' => 'com a nobreza', 'fonte' => 'Nobre de Teste' }],
    )
  end
end
