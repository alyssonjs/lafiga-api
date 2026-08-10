# frozen_string_literal: true

require 'spec_helper'
require 'json'
require_relative '../../app/data/open5e_translation'
require_relative '../../app/services/open5e_monster_mapper'

# Specs do mapper Open5e (SRD 5.1) -> MonsterEntry. PORO puro: nao precisa do
# Rails/DB. Fixtures sao criaturas REAIS do snapshot (spec/fixtures/open5e).
RSpec.describe Open5eMonsterMapper do
  def fixture(name)
    JSON.parse(File.read(File.expand_path("../fixtures/open5e/#{name}.json", __dir__)))
  end

  describe 'Goblin (SRD)' do
    subject(:row) { described_class.call(fixture('goblin')) }

    it 'mapeia identidade + enums para PT' do
      expect(row['id']).to eq('open5e-goblin')
      expect(row['name']).to eq('Goblin')
      expect(row['nameEN']).to eq('Goblin')
      expect(row['size']).to eq('Pequeno')
      expect(row['type']).to eq('Humanoide')
      expect(row['alignment']).to eq('Neutro e Mau')
      expect(row['source']).to eq('open5e')
    end

    it 'converte CR float -> string e copia xp/ac/hp' do
      expect(row['cr']).to eq('1/4')
      expect(row['xp']).to eq(50)
      expect(row['ac']).to eq(15)
      expect(row['hp']).to eq(7)
    end

    it 'mapeia stats, speed (dropa 0), senses e skills PT' do
      expect(row['stats']).to include('str' => 8, 'dex' => 14)
      expect(row['speed']).to eq('walk' => 30, 'swim' => 15, 'climb' => 15)
      expect(row['speed']).not_to have_key('fly')
      expect(row['senses']).to include('darkvision' => 60, 'passivePerception' => 9)
      expect(row['skills']).to eq('Furtividade' => 6)
    end

    it 'PARSEIA o ataque do desc (fonte confiavel), NAO do damage_type bugado' do
      atk = row['actions'].find { |a| a['attack'] }
      expect(atk['description'])
        .to eq('Ataque Corpo a Corpo com Arma: +4 para acertar, alcance 1,5 m, um alvo. Acerto: 5 (1d6+2) cortante.')
      # o campo estruturado da Open5e dizia "thunder" (bug); o desc diz slashing
      expect(atk['attack']).to include('kind' => 'melee', 'toHit' => 4, 'reach' => '1,5 m')
      expect(atk['attack']['damage']).to eq('dice' => '1d6+2', 'avg' => 5, 'type' => 'cortante')
      expect(atk['attacksRaw']).to be_an(Array) # cru preservado p/ referencia
    end

    it 'parseia dano FIXO sem dado (bestas CR 0): "Hit: N tipo damage"' do
      row = described_class.call(
        'key' => 'srd_bat', 'name' => 'Bat',
        'actions' => [{ 'name' => 'Bite', 'action_type' => 'ACTION',
                        'desc' => 'Melee Weapon Attack: +0 to hit, reach 5 ft., one creature. Hit: 1 piercing damage.' }]
      )
      atk = row['actions'].first
      expect(atk['attack']['damage']).to eq('avg' => 1, 'type' => 'perfurante') # sem 'dice'
      expect(atk['description']).to eq('Ataque Corpo a Corpo com Arma: +0 para acertar, alcance 1,5 m, um alvo. Acerto: 1 perfurante.')
    end

    it 'nao parseia "ataque" sem dano (efeito puro vira prosa)' do
      row = described_class.call(
        'key' => 'srd_rug', 'name' => 'Rug',
        'actions' => [{ 'name' => 'Smother', 'action_type' => 'ACTION',
                        'desc' => 'Melee Weapon Attack: +5 to hit, reach 5 ft., one creature. Hit: The creature is grappled (escape DC 13).' }]
      )
      expect(row['actions'].first['attack']).to be_nil
      expect(row['actions'].first['description']).to include('grappled') # prosa EN preservada
    end

    it 'anexa a atribuicao OGL/SRD' do
      expect(row['attribution']).to include(
        'license' => 'OGL-1.0a', 'document_key' => 'srd-2014',
        'publisher' => 'Wizards of the Coast'
      )
    end

    it 'omite listas vazias (sem conditionImmunities)' do
      expect(row).not_to have_key('conditionImmunities')
    end
  end

  describe 'Contrato: campos obrigatorios do MonsterEntry sempre presentes' do
    # Front trata languages/speed/stats/senses/actions como obrigatorios; se o
    # mapper os OMITIR quando vazios, o modal quebra (languages.length de undefined).
    subject(:row) do
      described_class.call('key' => 'srd_x', 'name' => 'X') # criatura minima, sem nada
    end

    it 'emite languages: [] mesmo sem idiomas' do
      expect(row).to have_key('languages')
      expect(row['languages']).to eq([])
    end

    it 'emite speed e actions mesmo vazios' do
      expect(row).to have_key('speed')
      expect(row).to have_key('actions')
    end
  end

  describe 'Lich (SRD) — imunidades de condicao + dano nao magico' do
    subject(:row) { described_class.call(fixture('lich')) }

    it 'traduz condition immunities EN->PT (playbook de condicoes)' do
      expect(row['conditionImmunities'])
        .to eq(%w[encantado exaustao amedrontado paralisado envenenado])
    end

    it 'monta damageImmunities do DISPLAY (array achata "nao magico" em tipos totais)' do
      # display SRD do lich: "poison; bludgeoning, piercing, and slashing from
      # nonmagical attacks" — NAO deve listar contundente/perfurante/cortante
      # como imunidades TOTAIS (o array estruturado erroneamente o faz).
      expect(row['damageImmunities'])
        .to eq(['veneno', 'contundente, perfurante e cortante de armas nao magicas'])
    end

    it 'separa acoes lendarias' do
      expect(row['legendaryActions']).to be_a(Hash)
      expect(row['legendaryActions']['actions']).not_to be_empty
      expect(row['legendaryActions']['description']).to include('acoes lendarias')
    end
  end

  describe 'CR float -> string (casos)' do
    def cr_of(v)
      described_class.call('key' => 'srd_x', 'name' => 'X', 'challenge_rating' => v)['cr']
    end

    it { expect(cr_of(0.125)).to eq('1/8') }
    it { expect(cr_of(0.25)).to eq('1/4') }
    it { expect(cr_of(0.5)).to eq('1/2') }
    it { expect(cr_of(2.0)).to eq('2') }
    it { expect(cr_of(nil)).to eq('0') }
  end

  describe Open5eTranslation do
    it 'traduz enums e converte pes->metros' do
      expect(described_class.condition('frightened')).to eq('amedrontado')
      expect(described_class.condition('poisoned')).to eq('envenenado')
      expect(described_class.damage('fire')).to eq('fogo')
      expect(described_class.type('fiend')).to eq('Infernal')
      expect(described_class.size('gargantuan')).to eq('Colossal')
      expect(described_class.feet_to_meters_str(5)).to eq('1,5 m')
      expect(described_class.feet_to_meters_str(30)).to eq('9 m')
      expect(described_class.feet_to_meters_str(120)).to eq('36 m')
    end

    it 'faz fallback sem perder dado quando falta mapping' do
      expect(described_class.condition('webbed')).to eq('webbed')
    end

    describe '.damage_display_list (display autoritativo)' do
      it 'lista simples por virgula' do
        expect(described_class.damage_display_list('fire, poison')).to eq(%w[fogo veneno])
      end

      it 'resistencia fisica TOTAL quando nao ha "nonmagical"' do
        expect(described_class.damage_display_list('bludgeoning, piercing, slashing'))
          .to eq(%w[contundente perfurante cortante])
      end

      it 'clausula nao-magica separada do tipo total (";")' do
        got = described_class.damage_display_list('cold; bludgeoning, piercing, and slashing from nonmagical attacks')
        expect(got).to eq(['frio', 'contundente, perfurante e cortante de armas nao magicas'])
      end

      it 'excecao adamantina/prateada e subconjunto de tipos fisicos' do
        expect(described_class.damage_display_list('piercing and slashing from nonmagical attacks not made with adamantine weapons'))
          .to eq(['perfurante e cortante de armas nao magicas (exceto adamantinas)'])
        expect(described_class.damage_display_list('bludgeoning, piercing, and slashing from nonmagical attacks not made with silvered weapons'))
          .to eq(['contundente, perfurante e cortante de armas nao magicas (exceto prateadas)'])
      end
    end
  end
end
