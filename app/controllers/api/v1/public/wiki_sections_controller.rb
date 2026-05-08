# frozen_string_literal: true

# GET /api/v1/public/wiki_sections — leitura aberta (sem token).
#
# Por que publico: a sidebar da Wiki e visivel para qualquer visitante e
# nao revela nenhum dado sensivel — apenas a estrutura de navegacao do
# lore do mundo. Chamado pelo `WikiSectionsContext` no boot do front.
class Api::V1::Public::WikiSectionsController < ApplicationController
  def index
    sections = WikiSection.ordered.map(&:as_payload)
    render json: { wiki_sections: sections, meta: { total: sections.length } }, status: :ok
  end
end
