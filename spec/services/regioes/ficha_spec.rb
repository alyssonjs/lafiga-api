# frozen_string_literal: true

require 'rails_helper'

# A ficha de região (L1.1; plano A14 e B3): o arquivo de Argoba carrega e é conferido inteiro ao carregar.
RSpec.describe Regioes::Ficha do
  let(:argoba) { described_class.de('argoba') }

  # uma cópia funda e mexível da ficha de Argoba, para estragar um pedaço
  def ficha_com
    copia = Marshal.load(Marshal.dump(argoba))
    yield copia
    copia
  end

  def erro_de(ficha)
    described_class.confere!(ficha, origem: 'teste')
    nil
  rescue ArgumentError => e
    e.message
  end

  describe 'Argoba' do
    it 'fica em Zandria, com floresta, costa e pequenas cavernas' do
      expect(argoba).to include('chave' => 'argoba', 'nome' => 'Argoba', 'reino' => 'zandria')
      expect(argoba['biomas'].keys).to eq(%w[floresta costa subterraneo])
      expect(argoba['biomas']['floresta']['recursos']).to include('madeira', 'ervas')
      expect(argoba['biomas']['costa']['clima']).to eq(%w[chuva tempestade])
    end

    it 'tem fauna em cada bioma, sem repetir criatura no mesmo bioma' do
      argoba['biomas'].each do |bioma, b|
        expect(b['fauna']).not_to be_empty, bioma
        expect(b['fauna']).to eq(b['fauna'].uniq), bioma
      end
    end

    it 'dá a CD do acampamento por território (plano A15)' do
      expect(argoba['cd_acampamento']).to eq('comum' => 10, 'infestado' => 15, 'amaldicoado' => 18)
    end

    it 'traz a campanha com a corrente de setores na ordem do GDD §91' do
      campanha = argoba['campanha']
      expect(campanha).to include('chave' => 'retomada-de-argoba', 'nome' => 'A Retomada de Argoba')
      expect(campanha['ameaca']).to include('chave' => 'colonizador', 'natureza' => 'um poder sombrio', 'tropas' => [])
      expect(campanha['etapas'].first).to eq('assentamento')
      expect(campanha['setores'].map { |s| s['chave'] })
        .to eq(%w[assentamento floresta buzios estrada posto periferia primeiro-distrito])
    end

    it 'o assentamento tem o tamanho do mapa (L1.2); os outros setores ainda não' do
      setores = argoba['campanha']['setores']
      expect(setores.first['mapa']).to eq('colunas' => 200, 'linhas' => 200)
      expect(setores.drop(1).map { |s| s['mapa'] }).to all(be_nil)
    end

    it 'cada terreno de coleta tem erva no herbs_seed.json (a coleta do L2.5 sai de lá)' do
      ervas = JSON.parse(File.read(Rails.root.join('db/data/herbs_seed.json')))['materiais']
      terrenos = ervas.flat_map { |e| Array(e.dig('foraging', 'locations')) }.uniq

      argoba['biomas'].each_value do |b|
        expect(terrenos).to include(*b['coleta'])
      end
    end

    it 'vem congelada: quem lê não muda a ficha dos outros' do
      expect(argoba).to be_frozen
      expect(argoba['campanha']['setores'].first).to be_frozen
    end
  end

  it 'região sem ficha é erro' do
    expect { described_class.de('atlantida') }.to raise_error(ArgumentError, /região sem ficha: atlantida/)
  end

  describe 'a conferência' do
    it 'aceita a ficha de Argoba como está' do
      expect(erro_de(ficha_com { |_| })).to be_nil
    end

    it 'recusa número quebrado (só inteiros, D11)' do
      ficha = ficha_com { |f| f['campanha']['setores'][0]['pressao_selvagem'] = 20.5 }
      expect(erro_de(ficha)).to include('só inteiros')
    end

    it 'recusa bioma fora do vocabulário' do
      ficha = ficha_com { |f| f['biomas']['selva'] = f['biomas'].delete('floresta') }
      expect(erro_de(ficha)).to include('bioma desconhecido: selva')
    end

    it 'recusa estação que o calendário não tem' do
      ficha = ficha_com { |f| f['biomas']['floresta']['estacoes']['moncao'] = 'chuva' }
      expect(erro_de(ficha)).to include('estação desconhecida em floresta: moncao')
    end

    it 'recusa clima que o MVP não tem' do
      ficha = ficha_com { |f| f['biomas']['costa']['clima'] << 'nevasca' }
      expect(erro_de(ficha)).to include('clima desconhecido em costa: nevasca')
    end

    it 'recusa criatura repetida no mesmo bioma' do
      ficha = ficha_com { |f| f['biomas']['floresta']['fauna'] << 'open5e-wolf' }
      expect(erro_de(ficha)).to include('fauna repetida em floresta: open5e-wolf')
    end

    it 'recusa pressão fora de 0..100' do
      ficha = ficha_com { |f| f['campanha']['setores'][1]['influencia'] = 101 }
      expect(erro_de(ficha)).to include('floresta: influencia fora de 0..100')
    end

    it 'recusa território sem CD de acampamento' do
      ficha = ficha_com { |f| f['campanha']['setores'][2]['territorio'] = 'sagrado' }
      expect(erro_de(ficha)).to include('buzios: territorio desconhecido: sagrado')
    end

    it 'recusa setor repetido' do
      ficha = ficha_com { |f| f['campanha']['setores'] << f['campanha']['setores'][0].dup }
      expect(erro_de(ficha)).to include('setor repetido: assentamento')
    end

    it 'recusa mapa de setor fora do tamanho que o BattleMap aceita' do
      ficha = ficha_com { |f| f['campanha']['setores'][0]['mapa'] = { 'colunas' => 2000, 'linhas' => 200 } }
      expect(erro_de(ficha)).to include('assentamento: mapa fora de')
    end

    it 'recusa a ficha sem uma parte' do
      ficha = ficha_com { |f| f.delete('cd_acampamento') }
      expect(erro_de(ficha)).to include('falta cd_acampamento')
    end
  end

  it 'o nome do arquivo é a chave da região' do
    Dir.mktmpdir do |pasta|
      caminho = File.join(pasta, 'outra.yml')
      File.write(caminho, File.read(Rails.root.join('config/mundo/regioes/argoba.yml')))
      expect { described_class.carrega(caminho) }.to raise_error(ArgumentError, /a chave argoba não é o nome do arquivo \(outra\)/)
    end
  end
end
