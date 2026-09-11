require 'rails_helper'

# O sanitizador é a FRONTEIRA. Forma errada aqui não quebra "a classe do
# mestre" — quebra a criação de personagem, porque `ClassRules.find` é lido em
# runtime por 33 pontos.
RSpec.describe Klasses::RulesOverlay, type: :service do
  def limpa(h) = described_class.sanitize(h)

  # ⚠️ Meio lote gravado é pior do que lote nenhum: a classe fica com a chave
  # boa aplicada e a má fora, e ninguém sabe qual é qual.
  it 'com QUALQUER erro não devolve nada — nada fica pela metade', :aggregate_failures do
    limpo, erros = limpa({ 'hit_die' => 10, 'velocidade' => 9 })
    expect(erros).not_to be_empty
    expect(limpo).to eq({})
  end

  it 'aceita as 17 chaves medidas e recusa o resto', :aggregate_failures do
    expect(limpa({ 'feature_rules' => { 'x' => 1 } }).last).to be_empty
    expect(limpa({ 'inventada' => 1 }).last.join).to include('inventada')
  end

  describe 'grafia canônica' do
    it 'atributo por extenso vira sigla' do
      expect(limpa({ 'primary_abilities' => ['Força', 'destreza'] }).first['primary_abilities']).to eq(%w[FOR DES])
    end

    it 'sigla inglesa também' do
      expect(limpa({ 'saving_throws' => %w[str wis] }).first['saving_throws']).to eq(%w[FOR SAB])
    end

    it 'atributo inexistente é recusado' do
      expect(limpa({ 'saving_throws' => %w[FOR BANANA] }).last.join).to include('BANANA')
    end

    it 'dado de vida vira `dN` venha número ou texto', :aggregate_failures do
      expect(limpa({ 'hit_die' => 8 }).first['hit_die']).to eq('d8')
      expect(limpa({ 'hit_die' => 'D6' }).first['hit_die']).to eq('d6')
      expect(limpa({ 'hit_die' => 'grande' }).last).not_to be_empty
    end
  end

  describe 'escolhas' do
    it '`choose` maior que as opções é recusado' do
      expect(limpa({ 'skill_proficiencies' => { 'choose' => 3, 'options' => %w[A] } }).last).not_to be_empty
    end

    it '`subclass` sem `choose_level` é recusada' do
      expect(limpa({ 'subclass' => { 'options' => {} } }).last).not_to be_empty
    end

    it '`subclass` mantém id e nome de cada opção' do
      out = limpa({ 'subclass' => { 'choose_level' => 3, 'options' => { 'champion' => { 'name' => 'Campeão' } } } }).first
      expect(out['subclass']['options']['champion']).to eq({ 'id' => 'champion', 'name' => 'Campeão' })
    end
  end

  # ⚠️ `feature_rules` é o catálogo que o motor de combate consome, com forma
  # por feature. Inventar um esquema agora desligaria mecânica em silêncio —
  # a fase 6 do plano trata dele, com auditoria antes.
  it 'deixa `feature_rules` passar como objeto livre, de propósito' do
    corpo = { 'fighting_style' => { 'options' => { 'Defesa' => { 'ac_bonus' => 1 } } } }
    expect(limpa({ 'feature_rules' => corpo }).first['feature_rules']).to eq(corpo)
  end

  it '`nil` é soltar a chave, não gravar vazio' do
    expect(limpa({ 'hit_die' => nil })).to eq([{}, []])
  end
end
