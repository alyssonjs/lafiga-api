# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# FASE 1 dos quatro tipos restantes. Cada um pede uma coisa diferente, e tratá-los
# igual daria resultado errado — foi por isso que a fase começou medindo os
# consumidores, e não escrevendo código.
RSpec.describe 'leitores de perícia, salvaguarda, armadura e arma (fase 1)' do
  before(:all) do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  before do
    Proficiency.where(category: %w[skill saving_throw armor weapon weapon_category]).destroy_all
    [Proficiencies::SkillReader, Proficiencies::SavingThrowReader,
     Proficiencies::ArmorReader, Proficiencies::WeaponReader].each(&:reset_cache!)
    %w[dnd:seed_proficiency_core dnd:seed_proficiency_weapons].each do |t|
      Rake::Task[t].reenable
      Rake::Task[t].invoke
    end
    [Proficiencies::SkillReader, Proficiencies::SavingThrowReader,
     Proficiencies::ArmorReader, Proficiencies::WeaponReader].each(&:reset_cache!)
  end

  after do
    [Proficiencies::SkillReader, Proficiencies::SavingThrowReader,
     Proficiencies::ArmorReader, Proficiencies::WeaponReader].each(&:reset_cache!)
  end

  describe 'PERÍCIA — tolerância a acento e caixa' do
    it 'resolve o que as fichas antigas escreveram sem acento' do
      # Medido: as 4 fontes já concordavam nas mesmas 18, então o ganho aqui é
      # só a tolerância. Paridade nas 69 fichas: 0 divergentes.
      expect(Proficiencies::SkillReader.canonicalize(%w[Intuicao INTUIÇÃO]))
        .to eq(['Intuição'])
    end
  end

  describe '⚠️ SALVAGUARDA — a saída NÃO muda' do
    it 'continua sendo a chave de atributo, não o nome' do
      # É a chave que o front usa para montar a linha de TR. Devolver "Destreza"
      # quebraria a tela — por isso este leitor tem método próprio, e não
      # `canonicalize`.
      expect(Proficiencies::SavingThrowReader.ability_keys(%w[DES Carisma])).to eq(%w[cha dex])
    end

    it 'as DUAS grafias colapsam — era o que o 4º mapa de tradução fazia' do
      # `Klass.saving_throws` guarda "Destreza"; a ficha guarda "DES".
      expect(Proficiencies::SavingThrowReader.ability_keys(['Destreza', 'DES'])).to eq(['dex'])
    end

    it '⚠️ DESCARTA o desconhecido, em vez de o preservar' do
      # Única categoria em que descartar é mais seguro: o consumidor espera uma
      # chave de atributo, e "Klingon" produziria uma linha de TR inexistente.
      expect(Proficiencies::SavingThrowReader.ability_keys(%w[DES Klingon])).to eq(['dex'])
    end
  end

  describe 'ARMADURA — três vocabulários, uma linha' do
    it 'slug inglês, pt-BR e rótulo caem no mesmo canônico' do
      expect(Proficiencies::ArmorReader.canonicalize(%w[light leve])).to eq(['Armaduras Leves'])
      expect(Proficiencies::ArmorReader.canonicalize(['medium', 'média', 'Armaduras Médias']))
        .to eq(['Armaduras Médias'])
    end
  end

  describe '⚠️ ARMA — categoria e arma no MESMO array' do
    it 'a linha exata da ficha 87 sai inteira e legível' do
      # ["simple", "hand_crossbow", "longsword", "rapieiras", "shortsword"]
      # é categoria + arma + arma + arma-em-pt-BR-plural + arma, tudo junto.
      expect(
        Proficiencies::WeaponReader.canonicalize(
          %w[simple hand_crossbow longsword rapieiras shortsword],
        ),
      ).to eq(['Armas Simples', 'Besta de Mão', 'Espada Longa', 'Rapieira', 'Espada Curta'])
    end

    it '⚠️ o plural pt-BR que a ficha mostrava CRU agora vira nome' do
      # Hoje a ficha exibe "adagas", "bordoes", "macas", "clavas" em minúsculas:
      # `prettifyProficiencyList` (front) não conhece esses plurais. O catálogo
      # conhece — é o ganho visível desta fase.
      expect(Proficiencies::WeaponReader.canonicalize(%w[adagas bordoes macas clavas foices]))
        .to eq(['Adaga', 'Bordão', 'Maça', 'Porrete', 'Foice Curta'])
    end

    it 'duas grafias da mesma arma viram UMA linha' do
      expect(Proficiencies::WeaponReader.canonicalize(['longsword', 'Espadas Longas', 'espada longa']))
        .to eq(['Espada Longa'])
    end
  end

  describe 'as garantias da base valem nos quatro' do
    it 'TOLERANTE (menos a salvaguarda, que é o caso à parte)' do
      expect(Proficiencies::WeaponReader.canonicalize(['Adaga', 'Espada Laser']))
        .to eq(['Adaga', 'Espada Laser'])
      expect(Proficiencies::ArmorReader.canonicalize(['Armadura de Vibranium']))
        .to eq(['Armadura de Vibranium'])
    end

    it 'DEGRADA PARA IDENTIDADE com o catálogo vazio' do
      Proficiency.where(category: %w[armor weapon weapon_category]).destroy_all
      [Proficiencies::ArmorReader, Proficiencies::WeaponReader].each(&:reset_cache!)
      expect(Proficiencies::ArmorReader.canonicalize(['light'])).to eq(['light'])
      expect(Proficiencies::WeaponReader.canonicalize(['longsword'])).to eq(['longsword'])
    end

    it '⚠️ e cada leitor só enxerga a SUA categoria' do
      # Sem isto o catálogo perderia a razão de existir: separar tipos.
      expect(Proficiencies::ArmorReader.canonicalize(['longsword'])).to eq(['longsword'])
      expect(Proficiencies::SkillReader.canonicalize(['light'])).to eq(['light'])
    end
  end
end
