# frozen_string_literal: true

require 'rails_helper'

# FASE 0 do editor de raças — OVERLAY no banco por cima do YAML.
#
# A mecânica de raça vive em `config/race_rules.yml`, lida em runtime. Isso
# torna o catálogo editável só por deploy, e uma raça criada apenas no banco
# levanta `ArgumentError: race not found` no provisioning.
#
# ⚠️ A propriedade que sustenta tudo: com `rules_json` VAZIO, esta camada é a
# IDENTIDADE. Medido à parte contra a versão de HEAD — as 40 combinações
# raça×sub-raça e o bundle inteiro saem idênticos byte a byte.
RSpec.describe RaceRules, 'overlay de regras no banco', type: :service do
  let!(:raca) do
    Race.find_by(api_index: 'tiefling') || Race.create!(name: 'Tiefling', api_index: 'tiefling')
  end

  before { RaceRules.reload! }
  after do
    raca.update_columns(rules_json: {})
    SubRace.where(race_id: raca.id).update_all(rules_json: {})
    RaceRules.reload!
  end

  describe 'sem nada gravado' do
    it 'o overlay está vazio e o YAML manda', :aggregate_failures do
      ov = described_class.overlay
      expect(ov[:races]).to be_blank
      expect(described_class.rules.size).to be_positive
      expect(described_class.find('tiefling')).to be_present
    end

    it '⚠️ `aplicar_overlay` devolve o MESMO objeto — é a identidade' do
      base = { races: { x: { name: 'X' } }, trait_definitions: {} }
      expect(described_class.aplicar_overlay(base, {})).to equal(base)
      expect(described_class.aplicar_overlay(base, { races: {}, subraces: {} })).to equal(base)
    end
  end

  describe 'o que o mestre grava vence' do
    it 'sobrepõe a chave e o resto do YAML fica', :aggregate_failures do
      antes = described_class.find('tiefling')
      tracos_antes = Array(antes[:traits]).size

      raca.update!(rules_json: { 'speed' => '12m' })
      depois = described_class.find('tiefling')

      expect(depois[:speed]).to eq('12m')
      expect(Array(depois[:traits]).size).to eq(tracos_antes)
      expect(depois[:name]).to eq(antes[:name])
    end

    it 'limpar devolve o valor do YAML' do
      original = described_class.find('tiefling')[:speed]
      raca.update!(rules_json: { 'speed' => '99m' })
      expect(described_class.find('tiefling')[:speed]).to eq('99m')

      raca.update!(rules_json: {})
      expect(described_class.find('tiefling')[:speed]).to eq(original)
    end

    it '⚠️ a chave do overlay vence INTEIRA — não soma com a base' do
      # `deep_merge` CONCATENA arrays (é o que faz os traços da sub-raça somarem
      # aos da raça). Aqui isso seria desastre: o mestre que TIRA um traço da
      # lista veria o traço voltar, somado pela base, sem nada a explicar.
      raca.update!(rules_json: { 'traits' => [{ 'key' => 'darkvision' }] })
      expect(Array(described_class.find('tiefling')[:traits]).size).to eq(1)
    end

    it 'chave com `nil` é ignorada — não apaga o que a base tem' do
      antes = described_class.find('tiefling')[:speed]
      raca.update!(rules_json: { 'speed' => nil })
      expect(described_class.find('tiefling')[:speed]).to eq(antes)
    end
  end

  describe '⚠️ `custom_traits`: a raça declara traço próprio' do
    let(:proprio) do
      { 'custom_traits' => { 'traco_do_mestre' => {
        'name' => 'Traço do Mestre',
        'grants' => { 'defenses' => { 'resistance' => ['fogo'] } }
      } } }
    end

    it 'sobe para o catálogo GLOBAL de definições', :aggregate_failures do
      antes = described_class.trait_definitions.size
      raca.update!(rules_json: proprio)

      expect(described_class.trait_definitions.size).to eq(antes + 1)
      expect(described_class.trait_definitions[:traco_do_mestre][:name]).to eq('Traço do Mestre')
    end

    it '⚠️ e NÃO vaza como chave do nó da raça' do
      # Se ficasse no nó, `apply` devolveria `custom_traits` como se fosse regra
      # e quem consome o nó teria de saber ignorá-la.
      raca.update!(rules_json: proprio)
      expect(described_class.find('tiefling')).not_to have_key(:custom_traits)
    end

    it 'some ao limpar' do
      antes = described_class.trait_definitions.size
      raca.update!(rules_json: proprio)
      raca.update!(rules_json: {})
      expect(described_class.trait_definitions.size).to eq(antes)
    end
  end

  describe 'sub-raça' do
    # ⚠️ CRIA as duas se a base de teste não as tiver. A primeira versão fazia
    # `skip` e o exemplo passava sem exercitar nada — o mesmo modo de falha das
    # features de subclasse.
    let!(:sub) do
      SubRace.find_by(race_id: raca.id, api_index: 'infernal') ||
        SubRace.create!(race_id: raca.id, api_index: 'infernal', name: 'Infernal')
    end
    let!(:irma) do
      SubRace.find_by(race_id: raca.id, api_index: 'abissal') ||
        SubRace.create!(race_id: raca.id, api_index: 'abissal', name: 'Abissal')
    end

    it 'sobrepõe dentro da raça, sem tocar nas irmãs', :aggregate_failures do
      sub.update!(rules_json: { 'speed' => '3m' })
      no = described_class.find('tiefling')

      expect(no[:subraces][:infernal][:speed]).to eq('3m')
      expect(no[:subraces][:abissal]).to be_present
      expect(no[:subraces][:abissal][:speed]).to be_nil
      # E o nome da própria sub-raça, que vem do YAML, sobrevive.
      expect(no[:subraces][:infernal][:name]).to be_present
    end
  end

  describe '⚠️ degrada sem derrubar o catálogo' do
    it 'overlay indisponível devolve o YAML, não uma exceção', :aggregate_failures do
      allow(Race).to receive(:where).and_raise(ActiveRecord::StatementInvalid, 'coluna ausente')
      described_class.reload_overlay!

      expect { described_class.rules }.not_to raise_error
      expect(described_class.rules.size).to be_positive
    end
  end

  describe 'invalidação do cache' do
    it '⚠️ gravar a raça derruba o cache do overlay' do
      # Sem isto o mestre gravava e via o valor antigo — por até 12 horas.
      raca.update!(rules_json: { 'speed' => '77m' })
      expect(described_class.find('tiefling')[:speed]).to eq('77m')
    end

    it 'mexer só no `playable` NÃO derruba o cache' do
      expect(described_class).not_to receive(:reload_overlay!)
      raca.update!(playable: raca.playable)
      raca.update!(name: raca.name)
    end
  end
end
