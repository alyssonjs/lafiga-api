# frozen_string_literal: true

require 'rails_helper'

# AS SUBSTITUIÇÕES DOS MEMBROS (05/10): o Mestre troca o membro perdido por prótese, gancho, lâmina, perna de pau ou
# tapa-olho, com os efeitos dos itens mágicos e a arma natural; o jogador só mexe no visual. As penalidades do membro
# perdido (Guia do Mestre) somem com a substituição que RESTAURA.
RSpec.describe Sheets::Membros do
  def substituto(tipo, extra = {})
    { 'estado' => 'substituido', 'substituto' => { 'tipo' => tipo }.merge(extra) }
  end

  describe '.sanitize (o Mestre)' do
    it 'grava o substituto com o material e a cor do padrão do tipo', :aggregate_failures do
      limpo, erros = described_class.sanitize({ 'mao_direito' => substituto('gancho') }, actor_id: 7)
      expect(erros).to be_empty
      expect(limpo.dig('mao_direito', 'substituto')).to eq('tipo' => 'gancho', 'material' => 'metal', 'cor' => 'steel')
      expect(limpo.dig('mao_direito', 'by_user_id')).to eq(7)
    end

    it 'a prótese escolhe metal ou madeira; cor fora da rampa cai no padrão do material', :aggregate_failures do
      limpo, = described_class.sanitize({ 'braco_esquerdo' => substituto('protese', 'material' => 'madeira', 'cor' => 'oak') })
      expect(limpo.dig('braco_esquerdo', 'substituto')).to include('material' => 'madeira', 'cor' => 'oak')
      limpo, = described_class.sanitize({ 'braco_esquerdo' => substituto('protese', 'material' => 'madeira', 'cor' => 'gold') })
      expect(limpo.dig('braco_esquerdo', 'substituto')).to include('material' => 'madeira', 'cor' => 'maple')
      limpo, = described_class.sanitize({ 'braco_esquerdo' => substituto('gancho', 'material' => 'madeira') })
      expect(limpo.dig('braco_esquerdo', 'substituto')).to include('material' => 'metal')
    end

    it 'recusa o tipo que não serve ao membro (gancho no olho, perna de pau na mão)', :aggregate_failures do
      _, erros = described_class.sanitize({ 'olho_direito' => substituto('gancho') })
      expect(erros.join).to include('Gancho')
      _, erros = described_class.sanitize({ 'mao_direito' => substituto('perna_de_pau') })
      expect(erros).not_to be_empty
      _, erros = described_class.sanitize({ 'mao_direito' => substituto('foguete') })
      expect(erros).not_to be_empty
    end

    it 'os efeitos: só os permanentes dos itens mágicos, com valores simples', :aggregate_failures do
      limpo, = described_class.sanitize({ 'braco_direito' => substituto('protese', 'efeitos' => [
        { 'kind' => 'ability_bonus', 'ability' => 'str', 'value' => 2 },
        { 'kind' => 'heal', 'dice' => '2d4' },
        { 'kind' => 'resistance', 'damage_types' => %w[fire cold], 'lixo' => { 'a' => [1, { 'x' => Object.new }] } },
      ]) })
      efeitos = limpo.dig('braco_direito', 'substituto', 'efeitos')
      expect(efeitos.map { |e| e['kind'] }).to eq(%w[ability_bonus resistance])
      expect(efeitos.first).to eq('kind' => 'ability_bonus', 'ability' => 'str', 'value' => 2)
    end

    it 'a arma natural: dado válido, tipo de dano e propriedades da lista; `nil` = sem arma', :aggregate_failures do
      limpo, = described_class.sanitize({ 'mao_esquerdo' => substituto('lamina', 'arma' => {
        'nome' => 'Lâmina Serrilhada', 'dano' => '1D8', 'tipoDeDano' => 'slashing', 'propriedades' => %w[finesse heavy thrown light],
      }) })
      expect(limpo.dig('mao_esquerdo', 'substituto', 'arma')).to eq(
        'nome' => 'Lâmina Serrilhada', 'dano' => '1d8', 'tipoDeDano' => 'slashing', 'propriedades' => %w[finesse light],
      )
      limpo, = described_class.sanitize({ 'mao_esquerdo' => substituto('lamina', 'arma' => nil) })
      expect(limpo.dig('mao_esquerdo', 'substituto')).to have_key('arma')
      expect(limpo.dig('mao_esquerdo', 'substituto', 'arma')).to be_nil
      limpo, = described_class.sanitize({ 'mao_esquerdo' => substituto('lamina', 'arma' => { 'dano' => '1d7' }) })
      expect(limpo.dig('mao_esquerdo', 'substituto', 'arma')).to be_nil
    end
  end

  describe '.sanitize_visual (o jogador)' do
    let(:atual) { { 'perna_direito' => substituto('perna_de_pau', 'material' => 'madeira', 'cor' => 'maple', 'efeitos' => [{ 'kind' => 'speed_bonus', 'value' => 5 }]) } }

    it 'troca só a cor (e o material da prótese); o tipo e os efeitos ficam', :aggregate_failures do
      mexidos, erros = described_class.sanitize_visual({ 'perna_direito' => { 'cor' => 'walnut', 'tipo' => 'protese', 'efeitos' => [] } }, atual)
      expect(erros).to be_empty
      sub = mexidos.dig('perna_direito', 'substituto')
      expect(sub).to include('tipo' => 'perna_de_pau', 'cor' => 'walnut')
      expect(sub['efeitos']).to eq([{ 'kind' => 'speed_bonus', 'value' => 5 }])
    end

    it 'recusa o membro que não está substituído (o jogador não marca nem tira membro)' do
      _, erros = described_class.sanitize_visual({ 'mao_direito' => { 'cor' => 'gold' } }, atual)
      expect(erros).not_to be_empty
    end
  end

  describe '.penalidades e .maos_livres' do
    it 'inteiro: nada' do
      expect(described_class.penalidades({})).to eq(olhos: 0, orelhas: 0, maos: 0, pernas_sem_andar: 0, pernas_sem_equilibrio: 0)
    end

    it 'o maior leva os menores: sem o antebraço, sem a mão; sem a perna, sem o pé', :aggregate_failures do
      p = described_class.penalidades({ 'antebraco_direito' => { 'estado' => 'perdido' }, 'perna_esquerdo' => { 'estado' => 'perdido' } })
      expect(p[:maos]).to eq(1)
      expect(p[:pernas_sem_andar]).to eq(1)
      expect(p[:pernas_sem_equilibrio]).to eq(1)
    end

    it 'a prótese devolve tudo; a perna de pau devolve o andar (não o equilíbrio); gancho e tapa-olho não devolvem', :aggregate_failures do
      p = described_class.penalidades({
        'mao_direito' => substituto('protese'), 'mao_esquerdo' => substituto('gancho'),
        'pe_direito' => substituto('perna_de_pau'), 'olho_esquerdo' => substituto('tapa_olho'),
      })
      expect(p).to eq(olhos: 1, orelhas: 0, maos: 1, pernas_sem_andar: 0, pernas_sem_equilibrio: 1)
      expect(described_class.maos_livres({ 'braco_direito' => { 'estado' => 'perdido' }, 'mao_esquerdo' => substituto('lamina') })).to eq(0)
    end
  end

  describe '.substituicoes' do
    it 'só o maior de cada família de cada lado (a mão dentro do braço trocado não conta)' do
      lista = described_class.substituicoes({
        'braco_direito' => substituto('protese'), 'mao_direito' => substituto('gancho'),
        'pe_direito' => substituto('perna_de_pau'), 'olho_esquerdo' => { 'estado' => 'perdido' },
      })
      expect(lista.map(&:first)).to eq(%w[braco_direito pe_direito])
    end
  end
end
