# frozen_string_literal: true

# GET /api/v1/public/wiki_articles — leitura aberta (sem token).
#
# Por que público: o lore do mundo é o que a wiki existe para mostrar, e já
# aparecia para visitante deslogado quando vinha hardcoded do front. Trocar a
# fonte (código → banco) não podia estreitar quem lê, senão o visitante passava
# a ver uma wiki vazia.
#
# `?section=gods` devolve uma seção; sem o filtro devolve TUDO, que é o que o
# `WikiArticleContext` pede uma vez no boot — a wiki inteira são dezenas de
# artigos, não milhares, e uma ida só evita oito requisições em cascata ao
# abrir a sidebar.
class Api::V1::Public::WikiArticlesController < ApplicationController
  def index
    scope = WikiArticle.ordered
    scope = scope.in_section(params[:section]) if params[:section].present?

    articles = scope.map(&:as_payload)
    render json: { wiki_articles: articles, meta: { total: articles.length } }, status: :ok
  end
end
