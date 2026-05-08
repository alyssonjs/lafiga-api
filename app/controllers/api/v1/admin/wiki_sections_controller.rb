# frozen_string_literal: true

# CRUD da sidebar da Wiki — DM/Admin do site (`authorize_site_wide_dm`).
#
# Endpoints:
#   POST   /api/v1/admin/wiki_sections          — cria custom (built_in: false forcado)
#   PATCH  /api/v1/admin/wiki_sections/:id      — atualiza label/icon/desc/position
#                                                 (slug e built_in sao imutaveis)
#   DELETE /api/v1/admin/wiki_sections/:id      — destroy (rejeita built-ins com 422)
#   POST   /api/v1/admin/wiki_sections/reorder  — recebe { order: [<slug>, ...] }
#                                                 e regrava a coluna `position` em
#                                                 sequencia. Operacao idempotente.
#
# Player comum recebe 403 (alinhado com magic_items_authorization_spec).
class Api::V1::Admin::WikiSectionsController < ApplicationController
  before_action :authorize_site_wide_dm
  before_action :set_section, only: %i[update destroy]

  def create
    section = WikiSection.new(create_params.merge(built_in: false))
    # Posicao default: ao fim da lista. Evita ter que receber `position`
    # em todo POST (DM esta criando rapido pelo modal).
    section.position ||= (WikiSection.maximum(:position) || -1) + 1
    if section.save
      render json: { wiki_section: section.as_payload }, status: :created
    else
      render json: { errors: section.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @section.update(update_params)
      render json: { wiki_section: @section.as_payload }, status: :ok
    else
      render json: { errors: @section.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    if @section.built_in
      render json: { errors: ['Built-in sections cannot be removed'] }, status: :unprocessable_entity
      return
    end
    @section.destroy!
    head :no_content
  end

  # POST /api/v1/admin/wiki_sections/reorder
  # Body: { order: ["<slug>", ...] }
  # Persistencia: monta o mapeamento slug => idx e atualiza em transacao.
  # Slugs faltantes mantem suas posicoes atuais (movidos para o fim por
  # `position += offset` quando necessario? Nao — preserva absoluto). Em
  # outras palavras: o cliente envia a sequencia que considera "head" da
  # lista; tudo que ele nao mencionar fica como esta.
  def reorder
    order = Array(params[:order]).map(&:to_s)
    if order.empty?
      render json: { errors: ['order must be a non-empty array of slugs'] }, status: :unprocessable_entity
      return
    end

    sections_by_slug = WikiSection.where(slug: order).index_by(&:slug)
    missing = order - sections_by_slug.keys
    if missing.any?
      render json: { errors: ["Unknown slugs: #{missing.join(', ')}"] }, status: :unprocessable_entity
      return
    end

    WikiSection.transaction do
      order.each_with_index do |slug, idx|
        sections_by_slug.fetch(slug).update_columns(position: idx, updated_at: Time.current)
      end
    end

    payload = WikiSection.ordered.map(&:as_payload)
    render json: { wiki_sections: payload, meta: { total: payload.length } }, status: :ok
  end

  private

  def set_section
    @section = WikiSection.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { errors: ['Wiki section not found'] }, status: :not_found
  end

  def create_params
    params.require(:wiki_section).permit(:slug, :label, :description, :icon_name, :position)
  end

  # Slug e built_in sao imutaveis pos-criacao. Slug porque vira parte da
  # rota e renomear quebraria links salvos por jogadores; built_in porque
  # so o seed pode alterar.
  def update_params
    params.require(:wiki_section).permit(:label, :description, :icon_name, :position)
  end
end
