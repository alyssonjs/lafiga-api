# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# FASE 0 dos cinco tipos restantes: PERÍCIA, SALVAGUARDA, ARMADURA,
# CATEGORIA DE ARMA e ARMA. Com eles o catálogo fecha os OITO tipos.
RSpec.describe 'catálogo de perícia, salvaguarda, armadura e arma (fase 0)' do
  before(:all) do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  before do
    Proficiency.where(category: %w[skill saving_throw armor weapon weapon_category]).destroy_all
    %w[dnd:seed_proficiency_core dnd:seed_proficiency_weapons].each do |t|
      Rake::Task[t].reenable
      Rake::Task[t].invoke
    end
  end

  def resolve(v) = Proficiency.resolve(v)

  it 'fecha os cinco tipos com as contagens do PHB' do
    expect(Proficiency.of('skill').count).to eq(18)
    expect(Proficiency.of('saving_throw').count).to eq(6)
    expect(Proficiency.of('armor').count).to eq(4)
    expect(Proficiency.of('weapon_category').count).to eq(2)
    expect(Proficiency.of('weapon').count).to eq(37)
  end

  describe 'perícia — as 4 fontes já concordavam' do
    it 'as 18 do `SkillsCatalog` resolvem, e guardam o atributo' do
      # Zero divergência de vocabulário aqui: o problema da perícia é o front
      # repetir a lista em 30 arquivos, e isso é a fase 1.
      SkillsCatalog.all.each do |s|
        linha = resolve(s[:name])
        expect(linha).to be_present, "#{s[:name]} não catalogada"
        expect(linha.category).to eq('skill')
      end
      expect(resolve('Acrobacia').metadata['ability']).to eq('dex')
    end
  end

  describe 'salvaguarda — DUAS grafias para a mesma coisa' do
    it 'o por extenso do `Klass` e a abreviação da ficha caem na mesma linha' do
      # `Klass.saving_throws` guarda "Destreza"; a ficha guarda "DES".
      expect(resolve('Destreza')).to eq(resolve('DES'))
      expect(resolve('DES').metadata['abbrev']).to eq('DES')
      Klass.pluck(:saving_throws).flatten.compact.uniq.each do |v|
        expect(resolve(v)).to be_present, "#{v} não catalogada"
      end
    end
  end

  describe 'armadura — slug inglês, pt-BR e o rótulo exibido' do
    it 'as três formas resolvem para a mesma linha' do
      # A ficha guarda "light", `race_rules.yml` guarda "leve", e o que se
      # exibe é "Armaduras Leves" — que é o canônico.
      %w[light leve leves].each { |v| expect(resolve(v)&.name).to eq('Armaduras Leves') }
      expect(resolve('média')&.name).to eq('Armaduras Médias')
      expect(resolve('shield')&.name).to eq('Escudos')
    end
  end

  describe '⚠️ arma — os TRÊS vocabulários da mesma ficha' do
    it 'a linha exata da ficha 153 resolve inteira' do
      # ["simple", "hand_crossbow", "longsword", "rapieiras", "shortsword"]
      #  slug EN    slug EN         slug EN      pt-BR PLURAL   slug EN
      %w[simple hand_crossbow longsword rapieiras shortsword].each do |v|
        expect(resolve(v)).to be_present, "#{v} não resolve"
      end
      expect(resolve('simple').category).to eq('weapon_category')
      expect(resolve('longsword').category).to eq('weapon')
    end

    it 'o plural pt-BR que `class_rules.rb` grava cai na arma certa' do
      # ⚠️ Estes NÃO colapsam por normalização: "bordões" vira "bordoes" e
      # "Bordão" vira "bordao". Sem apelido explícito, cada um seria órfão.
      {
        'adagas' => 'Adaga', 'bordoes' => 'Bordão', 'clavas' => 'Porrete',
        'dardos' => 'Dardo', 'fundas' => 'Funda', 'foices' => 'Foice Curta',
        'lancas' => 'Lança', 'macas' => 'Maça', 'azagaias' => 'Azagaia',
        'bestas_leves' => 'Besta Leve', 'rapieiras' => 'Rapieira',
      }.each { |plural, canonico| expect(resolve(plural)&.name).to eq(canonico) }
    end

    it '⚠️ o rótulo PLURAL não vira linha própria' do
      # `proficiencyLabels.ts` produz "Espadas Longas" como label SEPARADO de
      # "Espada Longa". No catálogo é uma linha só, senão o mesmo aço viraria
      # duas proficiências.
      expect(resolve('Espadas Longas')).to eq(resolve('Espada Longa'))
      expect(resolve('Espadas Curtas')).to eq(resolve('Espada Curta'))
      expect(resolve('Arcos Longos')).to eq(resolve('Arco Longo'))
      expect(resolve('Rapieiras')).to eq(resolve('Rapieira'))
    end

    it '⚠️ os 5 nomes em que os DOIS catálogos do front discordam' do
      # `weaponDatabase.ts` (37 armas, 45 arquivos consomem) contra
      # `proficiencyLabels.ts` (o rótulo). O canônico é o do weaponDatabase —
      # mesma regra da ferramenta: a entidade vence o rótulo.
      {
        'Clava' => 'Porrete', 'Foice' => 'Foice Curta',
        'Lança Montada' => 'Lança de Montaria', 'Marreta' => 'Malho',
        'Mangual de Cabeça' => 'Morningstar',
      }.each { |rotulo, canonico| expect(resolve(rotulo)&.name).to eq(canonico) }
    end

    it 'o pt-BR de `race_rules.yml` resolve' do
      ['arco curto', 'arco longo', 'besta de mão', 'espada curta', 'espada longa',
       'machadinha', 'machado de batalha', 'martelo de guerra', 'martelo leve',
       'rapieira'].each { |v| expect(resolve(v)).to be_present, "#{v} não resolve" }
    end

    it '⚠️ "armas" NÃO foi catalogado' do
      # 3 fichas de Bruxo têm ["armas", "simple"]. Catalogá-lo seria mentir:
      # não é proficiência, é fragmento. Fica em quarentena na auditoria, com o
      # motivo, e sai numa limpeza de DADO — que é outra fase.
      expect(resolve('armas')).to be_nil
    end
  end

  it 'é idempotente' do
    antes = [Proficiency.count, ProficiencyAlias.count]
    %w[dnd:seed_proficiency_core dnd:seed_proficiency_weapons].each do |t|
      Rake::Task[t].reenable
      Rake::Task[t].invoke
    end
    expect([Proficiency.count, ProficiencyAlias.count]).to eq(antes)
  end
end
