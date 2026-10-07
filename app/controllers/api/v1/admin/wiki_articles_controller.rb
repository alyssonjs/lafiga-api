# frozen_string_literal: true

# Escrita dos artigos da wiki — Mestre ou EDITOR (`authorize_content_editor`).
#
# Endpoints:
#   POST   /api/v1/admin/wiki_articles       — cria (section + slug + data)
#   PATCH  /api/v1/admin/wiki_articles/:id   — reescreve o `data` (o lápis)
#   DELETE /api/v1/admin/wiki_articles/:id   — apaga
#
# ⚠️ O `:id` da rota é o par `section/slug`, não a chave primária — o front
# navega por slug (`/wiki/deuses/editar/god-01`) e nunca conheceu o id do
# banco. Por isso `section` viaja junto em toda chamada.
#
# Quem pode: DM, Admin e Editor. O Editor NÃO passa em `authorize_site_wide_dm`
# — este é o único portão que ele atravessa, e é de propósito (ver
# `ApplicationController#authorize_content_editor`). Jogador comum recebe 403.
#
# As SEÇÕES da sidebar seguem só do Mestre (`WikiSectionsController`): decisão
# da mesa em 07/10 — o Editor reescreve, cria e apaga ARTIGO; a estrutura do
# site não é dele.
class Api::V1::Admin::WikiArticlesController < ApplicationController
  before_action :authorize_content_editor
  before_action :set_article, only: %i[update destroy]

  def create
    article = WikiArticle.new(
      section: params.dig(:wiki_article, :section),
      slug: params.dig(:wiki_article, :slug).presence || slug_sugerido,
      data: data_param
    )
    # Posição default: ao fim da seção. Evita exigir `position` de quem está só
    # escrevendo um artigo novo pelo lápis.
    article.position = (WikiArticle.in_section(article.section).maximum(:position) || -1) + 1

    if article.save
      render json: { wiki_article: article.as_payload }, status: :created
    else
      render json: { errors: article.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # O LÁPIS. Reescreve `data` por inteiro — o editor manda o registro completo,
  # como o formulário sempre fez.
  #
  # `section` e `slug` são imutáveis: renomear o slug quebraria link que um
  # jogador guardou, e mudar a seção é mover o artigo, que a mesa ainda não
  # pediu. `position` entra quando vem.
  def update
    atributos = { data: data_param }
    atributos[:position] = params.dig(:wiki_article, :position) if params.dig(:wiki_article, :position).present?

    if @article.update(atributos)
      render json: { wiki_article: @article.as_payload }, status: :ok
    else
      render json: { errors: @article.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @article.destroy!
    head :no_content
  end

  private

  def set_article
    @article = WikiArticle.in_section(params[:section]).find_by(slug: params[:id])
    return if @article

    render json: { errors: ['Wiki article not found'] }, status: :not_found
  end

  # `data` é formato aberto (cada seção tem os seus campos — ver `WikiArticle`),
  # então não há lista branca de chaves a permitir: o que o `wikiEditorConfigs`
  # desenhar, entra. O que o modelo guarda é o TETO (64 KB) e o tipo (objeto).
  #
  # ⚠️ `permit!` aqui é consciente e estreito: vale só para o sub-hash `data`,
  # nunca para os params de topo — `section`, `slug` e `position` são lidos um a
  # um logo acima.
  def data_param
    bruto = params.require(:wiki_article)[:data]
    return {} if bruto.blank?

    (bruto.respond_to?(:permit!) ? bruto.permit!.to_h : bruto).to_h
  end

  # Artigo novo sem slug: deriva do nome que o redator escreveu. Cai em
  # `artigo-<timestamp>` quando não há nome nenhum, para nunca gravar slug vazio
  # (a validação recusaria e o lápis morreria sem explicação).
  def slug_sugerido
    nome = data_param['name'].presence || data_param['title'].presence
    base = nome.to_s.parameterize.presence
    base ||= "artigo-#{Time.current.to_i}"
    base.first(40).sub(/-\z/, '')
  end
end
