# frozen_string_literal: true

# Semeadura cara que roda UMA vez por arquivo — e não vaza para os seguintes.
#
# ⚠️ `use_transactional_fixtures = true` envolve cada EXEMPLO numa transação,
# mas `before(:all)` roda FORA dela: o que ele cria sobrevive ao arquivo e fica
# no banco de teste até alguém recriar o schema.
#
# O estrago não é teórico. Medido em 16/09/2026 por isolamento (contagem
# antes/depois, banco limpo):
#   · `imported_sheets_http_e2e_spec` deixava 13 Klass e 144 SubKlass;
#   · `feat_rules_all_feats_shape_spec` e `feat_assignment_service_all_feats_spec`
#     deixavam 43 Feats cada; `level_up_service_feats_spec`, 1.
# Consequência: `admin/feats_spec` falhava 9 exemplos com "Name has already been
# taken" quando rodava DEPOIS deles — falha de ORDEM, não de código, que já
# custou duas investigações a acusar regressão inexistente.
#
# ⚠️ Trocar por `before(:each)` conserta o vazamento e paga caro: estes blocos
# semeiam catálogos inteiros (43 talentos, 144 sub-classes) e há arquivos com
# dezenas de exemplos. A saída é manter o `before(:all)` DENTRO de uma transação
# própria, desfeita no `after(:all)` — que é exatamente o que o Rails faz por
# exemplo. A transação do exemplo vira um savepoint aninhado nesta, e o rollback
# externo leva tudo embora.
#
# `joinable: false` é o mesmo parâmetro que o `use_transactional_tests` do Rails
# usa: sem ele, um `ActiveRecord::Base.transaction` do código sob teste se
# JUNTARIA a esta transação em vez de abrir um savepoint — e um `commit` lá
# dentro daria por encerrada a nossa, devolvendo o vazamento pela porta dos
# fundos.
#
# Uso, no lugar de `before(:all)`:
#
#   semeia_uma_vez do
#     ImportedSheetsSeeder.seed_all!
#   end
module SemeaduraIsolada
  def semeia_uma_vez(&bloco)
    before(:all) do
      ActiveRecord::Base.connection.begin_transaction(joinable: false)
      instance_eval(&bloco)
    end

    # Roda mesmo que a semeadura levante: o `before(:all)` que falha ainda deixa
    # o `after(:all)` correr, e sem este rollback o lixo ficaria PARA SEMPRE.
    after(:all) do
      ActiveRecord::Base.connection.rollback_transaction
    end
  end
end

RSpec.configure do |config|
  config.extend SemeaduraIsolada
end
