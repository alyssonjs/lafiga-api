# frozen_string_literal: true

require 'rails_helper'

# `Talentos.docx` é a fonte de verdade dos 41 talentos. O catálogo que semeia o banco
# (`config/feats_improved.yml`) tinha derivado dele: 10 nomes divergentes e TODAS as 44
# descrições eram frases-resumo de ~45 caracteres onde deveria estar a regra.
#
# Este spec prende nome e texto. A MECÂNICA (`special_rules`) é da auditoria à parte.
RSpec.describe 'Talentos × documento' do
  FONTE = Rails.root.join('spec/fixtures/talentos-fonte.txt')
  YML   = Rails.root.join('config/feats_improved.yml')

  # Lê o documento no formato NOME / PRÉ-REQUISITO / DESCRIÇÃO.
  def self.documento
    File.read(FONTE).split(/^NOME: /).reject { |b| b.strip.empty? }.map do |bloco|
      linhas = bloco.strip.split("\n")
      {
        nome: linhas.first.strip,
        desc: linhas.find { |l| l.start_with?('DESCRIÇÃO') }.to_s.sub('DESCRIÇÃO:', '').strip,
      }
    end
  end

  let(:doc)   { self.class.documento }
  let(:feats) { YAML.load_file(YML)['feats'] }
  let(:por_nome) { feats.values.index_by { |f| f['name'] } }

  # ⚠️ Descrição pode ser HTML (as bolinhas do livro). Comparar por TEXTO PURO,
  # trocando cada tag por ESPAÇO — remover a tag sem deixar nada colaria a última
  # palavra da frase-guia na primeira da bolinha, e a comparação passaria a mentir.
  def sem_tags(v)
    v.to_s.gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip
  end

  it 'a fonte tem 42 talentos — 41 do .docx mais o Ator, que só o livro tinha' do
    expect(doc.size).to eq(42)
  end

  it '⚠️ todo talento do documento está no catálogo, com o NOME do documento' do
    expect(doc.map { |d| d[:nome] } - por_nome.keys).to eq([])
  end

  it '⚠️ a descrição é a REGRA, não um resumo de uma linha' do
    doc.each do |d|
      expect(sem_tags(por_nome[d[:nome]]['description'])).to eq(d[:desc]), "descrição divergente: #{d[:nome]}"
    end
  end

  it 'o que sobra fora do documento é deliberado — tem fichas usando' do
    nomes = doc.map { |d| d[:nome] }
    # "Ator" saiu daqui: o livro (p.166) o tem, a omissão era do .docx
    expect((por_nome.keys - nomes).sort).to eq(['Especialista em Escudo'])
  end

  it 'nenhuma chave do YAML perdeu o `api_index` (é o que SheetFeat referencia)' do
    # renomear é trocar o NOME; a chave é contrato com as fichas já criadas
    %w[atacante_selvagem sniper_magico duelista_montado conjurador_de_batalha
       magico_iniciante mestre_arma_de_haste mente_agucada especialista_em_armas
       mestre_do_escudo mestre_de_armas_duplas].each do |k|
      expect(feats).to have_key(k), "chave sumiu: #{k}"
    end
  end
end
