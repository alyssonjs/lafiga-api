# frozen_string_literal: true

require 'rails_helper'

# CATRACA: semeadura cara não pode voltar a vazar para os arquivos seguintes.
#
# ⚠️ `use_transactional_fixtures = true` envolve cada EXEMPLO numa transação, mas
# `before(:all)` roda FORA dela — o que ele cria sobrevive ao arquivo e fica no
# banco de teste até alguém recriar o schema. Onze specs faziam isso, e o preço
# foi pago em investigação, não em bug: `admin/feats_spec` falhava 9 exemplos com
# "Name has already been taken" só por rodar DEPOIS deles, e a suíte acusava
# regressão inexistente. Medido por isolamento em 16/09/2026: o catálogo
# importado deixava 13 Klass + 144 SubKlass, e os specs de talento, 43 Feats.
#
# Nada no projeto barra o próximo `before(:all)` com semeadura — esta catraca
# barra. Ela lê o TEXTO dos specs de propósito: é a única forma de pegar o
# padrão antes de ele custar a próxima investigação.
RSpec.describe 'semeadura de catálogo em `before(:all)`' do
  # Os três semeadores que MEDIDAMENTE vazaram. Lista curta e específica em vez
  # de "qualquer create! num before(:all)": catraca barulhenta é catraca que
  # alguém desliga.
  def semeadores
    ['ImportedSheetsSeeder.seed_all!', 'ImportedSheetsSpellSeeder.seed_all!', 'Feat.find_or_create_by!']
  end

  def arquivos_de_spec
    # ⚠️ Este arquivo cita os semeadores por escrito; sem a exclusão, a catraca
    # acusaria a si mesma.
    Dir[Rails.root.join('spec', '**', '*_spec.rb')]
      .reject { |c| File.basename(c) == File.basename(__FILE__) }
  end

  def infratores
    arquivos_de_spec.filter_map do |caminho|
      linhas = File.read(caminho).split("\n")
      culpadas = linhas.each_index.select do |i|
        linha = linhas[i]
        next false unless linha.include?('before(:all)')
        # Comentário não é código: há prosa que fala de `before(:all)`, e foi ela
        # que fez a primeira varredura contar um infrator a mais.
        next false if linha.lstrip.start_with?('#')

        linhas[i, 6].any? { |seguinte| semeadores.any? { |s| seguinte.include?(s) } }
      end
      next if culpadas.empty?

      relativo = Pathname.new(caminho).relative_path_from(Rails.root)
      "#{relativo}:#{culpadas.map { |i| i + 1 }.join(',')}"
    end
  end

  it 'nenhum spec semeia catálogo num `before(:all)` cru' do
    expect(infratores).to eq([]), <<~AVISO
      Estes specs semeiam catálogo em `before(:all)`, que roda FORA da transação
      do exemplo — o que criarem fica no banco de teste e derruba os arquivos
      seguintes por colisão de unicidade:

        #{infratores.join("\n        ")}

      Troque `before(:all)` por `semeia_uma_vez` (spec/support/semeadura_isolada.rb):
      ele mantém a semeadura uma vez por arquivo, dentro de uma transação
      própria que o `after(:all)` desfaz. Nenhuma outra linha muda.
    AVISO
  end

  it 'e o helper continua abrindo E desfazendo a transação' do
    fonte = File.read(Rails.root.join('spec', 'support', 'semeadura_isolada.rb'))

    # ⚠️ `joinable: false` é load-bearing: sem ele, um `transaction` do código sob
    # teste se JUNTA a esta e um commit lá dentro devolve o vazamento.
    expect(fonte).to include('begin_transaction(joinable: false)')
    expect(fonte).to include('rollback_transaction')
  end
end
