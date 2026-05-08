# frozen_string_literal: true

# Cria a tabela `wiki_sections` — fonte de verdade da sidebar da Wiki.
#
# Contexto (Fase 2 do plano "DM administra a sidebar da Wiki"):
#   Antes a lista era hardcoded em `WikiLayout.tsx` no front, depois
#   evoluiu para um contexto React com persistência em `localStorage`
#   (Fase 1). Limitação: cada navegador via seu próprio set, então um
#   DM criar uma seção não aparecia para os jogadores. Esta migration
#   move o estado para o backend para que a configuração seja
#   compartilhada entre todos os usuários da campanha.
#
# Campos:
#   - `slug` (unique): identificador estável usado em rotas (`/wiki/c/<slug>`
#     para customs; built-ins têm path próprio). Built-ins têm slugs
#     canónicos (`planes`, `entities`, ...) — espelhados em
#     BUILT_IN_DEFINITIONS no `WikiSectionsContext.tsx`.
#   - `label`: texto exibido na sidebar / cards.
#   - `description` (nullable): legenda curta opcional (~80 chars).
#   - `icon_name`: nome do ícone Lucide (lookup em `WIKI_ICON_OPTIONS`).
#   - `position`: ordem na sidebar (asc). Mantido coerente em block via
#     endpoint dedicado de reorder.
#   - `built_in`: distingue seções do código (não removíveis) das criadas
#     pelo DM. DM pode renomear/reordenar built-ins, mas não destruí-las.
#
# Índices:
#   - `slug` único — usado para lookup em rotas e para impedir colisão
#     entre customs e built-ins.
#   - `[built_in, position]` — leitura típica é ORDER BY position; o filtro
#     por built_in serve para evitar que um cliente recém-bootado mostre só
#     customs enquanto built-ins ainda nao foram seedadas.
class CreateWikiSections < ActiveRecord::Migration[6.0]
  def change
    create_table :wiki_sections do |t|
      t.string :slug, null: false
      t.string :label, null: false
      t.text :description
      t.string :icon_name, null: false, default: 'BookOpen'
      t.integer :position, null: false, default: 0
      t.boolean :built_in, null: false, default: false
      t.timestamps
    end

    add_index :wiki_sections, :slug, unique: true
    add_index :wiki_sections, %i[built_in position]
  end
end
