# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subclasses::LevelsPatch do
  # A forma REAL medida em prod: linha 0 só com `rules`, linhas de nível com
  # `features` e `grants` (as chaves são 514 `level`, 502 `features`, 37
  # `grants`, 23 `rules`, 9 `choices`).
  let(:atual) do
    [
      { 'level' => 0, 'rules' => { 'superiority_dice' => { 'die_start' => 'd8' } } },
      { 'level' => 3,
        'features' => [{ 'name' => 'Combate Superior', 'description' => 'velha' }],
        'grants' => { 'proficiencies' => { 'tools' => ['Ferramentas de ferreiro'] } } },
      { 'level' => 7, 'features' => [{ 'name' => 'Conhecer a Manobra' }] }
    ]
  end

  describe 'granularidade' do
    it 'patch vazio devolve as MESMAS linhas — identidade, não cópia' do
      novo, erros = described_class.aplicar(atual, {})

      expect(erros).to eq([])
      expect(novo.size).to eq(3)
      novo.each_with_index { |linha, i| expect(linha).to equal(atual[i]) }
    end

    it 'mescla raso no nível tocado e preserva chave não tocada' do
      novo, erros = described_class.aplicar(
        atual,
        { 'set' => [{ 'level' => 3, 'features' => [{ 'name' => 'Combate Superior', 'description' => 'nova' }] }] }
      )

      expect(erros).to eq([])
      l3 = novo.find { |l| l['level'] == 3 }
      expect(l3['features'].first['description']).to eq('nova')
      expect(l3['grants']).to eq(atual[1]['grants'])
    end

    it 'não toca nos outros níveis — eles saem como o mesmo objeto' do
      novo, = described_class.aplicar(atual, { 'set' => [{ 'level' => 3, 'features' => [{ 'name' => 'X' }] }] })

      expect(novo.find { |l| l['level'] == 0 }).to equal(atual[0])
      expect(novo.find { |l| l['level'] == 7 }).to equal(atual[2])
    end

    it '`nil` numa chave SOLTA a chave (volta a valer a base do livro)' do
      novo, erros = described_class.aplicar(atual, { 'set' => [{ 'level' => 3, 'grants' => nil }] })

      expect(erros).to eq([])
      expect(novo.find { |l| l['level'] == 3 }).not_to have_key('grants')
      expect(novo.find { |l| l['level'] == 3 }['features']).to be_present
    end

    it 'nível novo entra ordenado' do
      novo, = described_class.aplicar(atual, { 'set' => [{ 'level' => 5, 'features' => [{ 'name' => 'Nova' }] }] })

      expect(novo.map { |l| l['level'] }).to eq([0, 3, 5, 7])
    end

    it '`remove` tira só o nível pedido' do
      novo, erros = described_class.aplicar(atual, { 'remove' => [7] })

      expect(erros).to eq([])
      expect(novo.map { |l| l['level'] }).to eq([0, 3])
    end
  end

  describe 'escritor canônico' do
    it 'aceita `level` em texto e GRAVA inteiro' do
      novo, erros = described_class.aplicar(atual, { 'set' => [{ 'level' => '5', 'features' => [{ 'name' => 'Nova' }] }] })

      expect(erros).to eq([])
      expect(novo.find { |l| l['level'] == 5 }['level']).to be_a(Integer)
    end

    it 'aceita chaves em símbolo (params) sem duplicar a linha' do
      novo, erros = described_class.aplicar(atual, { set: [{ level: 3, features: [{ name: 'Renomeada' }] }] })

      expect(erros).to eq([])
      expect(novo.map { |l| l['level'] }).to eq([0, 3, 7])
      expect(novo.find { |l| l['level'] == 3 }['features'].first['name']).to eq('Renomeada')
    end
  end

  describe '`rules` de topo (a linha de nível 0)' do
    it 'mescla no bloco existente' do
      novo, erros = described_class.aplicar(atual, { 'rules' => { 'superiority_dice' => { 'die_start' => 'd10' } } })

      expect(erros).to eq([])
      expect(novo.first['rules']['superiority_dice']['die_start']).to eq('d10')
    end

    it 'cria a linha 0 quando a sub-classe ainda não tem' do
      sem_zero = atual.reject { |l| l['level'].zero? }
      novo, = described_class.aplicar(sem_zero, { 'rules' => { 'spellcasting' => { 'ability' => 'INT' } } })

      expect(novo.map { |l| l['level'] }).to eq([0, 3, 7])
      expect(novo.first['rules']['spellcasting']['ability']).to eq('INT')
    end

    it '`nil` solta a linha 0 inteira quando ela só carregava `rules`' do
      novo, erros = described_class.aplicar(atual, { 'rules' => nil })

      expect(erros).to eq([])
      expect(novo.map { |l| l['level'] }).to eq([3, 7])
    end
  end

  describe 'erro não grava NADA' do
    it 'nem a parte válida do mesmo patch' do
      novo, erros = described_class.aplicar(
        atual,
        { 'set' => [{ 'level' => 3, 'features' => [{ 'name' => 'válida' }] }, { 'level' => 99 }] }
      )

      expect(erros.size).to eq(1)
      expect(erros.first).to include('`level` inválido')
      expect(novo).to eq(atual)
      expect(novo.find { |l| l['level'] == 3 }).to equal(atual[1])
    end

    it 'recusa chave desconhecida em vez de ignorá-la em silêncio' do
      novo, erros = described_class.aplicar(atual, { 'levels' => [] })

      expect(erros.first).to include('chaves desconhecidas no patch: levels')
      expect(novo).to eq(atual)
    end

    it 'exige `name` em cada feature' do
      _, erros = described_class.aplicar(atual, { 'set' => [{ 'level' => 3, 'features' => [{ 'description' => 'sem nome' }] }] })

      expect(erros.first).to include('`name` é obrigatório')
    end

    it 'recusa nível fora de 0..20' do
      _, erros = described_class.aplicar(atual, { 'set' => [{ 'level' => 21 }] })

      expect(erros.first).to include('`level` inválido')
    end
  end
end
