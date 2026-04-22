# Phase 10 — Bug 13 fix.
#
# Esta migration originalmente foi rodada em DEV (versao listada em
# `schema_migrations`) sem ter o arquivo correspondente commitado, gerando
# `********** NO FILE **********` no `db:migrate:status` e contribuindo para o
# schema cache stale do Puma que disparava `NoMethodError: undefined method
# `updated_at' for #<Sheet ...>` ao abrir a ficha de edicao.
#
# Como o estado canonico do schema esta em `db/schema.rb` (que ja reflete o
# resultado), restauramos um placeholder no-op aqui apenas para silenciar o
# warning e manter o historico linear. Qualquer modificacao real de schema
# deve ser feita por uma nova migration.
class BaselinePostRuntimeState < ActiveRecord::Migration[6.0]
  def change
    # no-op (placeholder restaurado em Phase 10 — schema canonico em
    # db/schema.rb).
  end
end
