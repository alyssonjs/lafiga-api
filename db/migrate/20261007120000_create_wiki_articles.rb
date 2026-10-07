# frozen_string_literal: true

# Cria a tabela `wiki_articles` — o TEXTO da wiki, que até aqui nunca existiu
# no banco.
#
# Contexto: a sidebar da wiki já fez esta viagem (`create_wiki_sections`,
# 20260xxx) justamente porque "cada navegador via o seu set, então um DM criar
# uma seção não aparecia para os jogadores". Os ARTIGOS ficaram para trás: o
# texto dos Deuses, Planos, Reinos e companhia está escrito à mão em cada
# página do front (`const SEED` em `WikiGods.tsx` e irmãs) e vive num
# `useState` (`WikiArticleContext`). Consequência, medida em 07/10/2026: o
# lápis que o Mestre já via salvava só na aba dele — recarregou, o texto
# voltava ao original, e nenhum jogador chegava a ver a mudança.
#
# Sem esta tabela não há papel de Editor nenhum: o lápis não teria onde gravar.
#
# Campos:
#   - `section`: slug da seção dona (`gods`, `planes`, ... ou o slug de uma
#     seção custom). String, e não FK para `wiki_sections`, porque as built-ins
#     são implícitas no código — em produção `wiki_sections` está VAZIA e a
#     wiki roda inteira das built-ins. Uma FK apagaria a wiki toda.
#   - `slug`: id estável do artigo (`god-01`), o mesmo que o front já usa e que
#     entra na rota de ver/editar. Renomear quebraria link guardado, então é
#     imutável depois de criado.
#   - `data` (jsonb): o registro inteiro, do jeito que a página desenha
#     (name, title, description, lore, domains[]...). Os campos variam por
#     seção — quem os declara é `wikiEditorConfigs.ts`, não o schema. Guardar
#     coluna a coluna obrigaria a uma migration por campo novo que o Mestre
#     inventasse; o formato aberto é o ponto.
#   - `position`: ordem dentro da seção.
#
# Índices:
#   - `[section, slug]` único — o par é a identidade do artigo, e impede que
#     dois POSTs concorrentes criem o mesmo id.
#   - `[section, position]` — a leitura típica é "a seção inteira, em ordem".
class CreateWikiArticles < ActiveRecord::Migration[6.0]
  def change
    create_table :wiki_articles do |t|
      t.string  :section,  null: false
      t.string  :slug,     null: false
      t.jsonb   :data,     null: false, default: {}
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :wiki_articles, %i[section slug], unique: true
    add_index :wiki_articles, %i[section position]
  end
end
