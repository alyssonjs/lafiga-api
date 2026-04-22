class Api::V1::Public::ClassChoicesController < ApplicationController
  # GET /api/v1/public/class_choices/:id
  #
  # :id é o nome do catálogo (ex.: 'metamagic'). Retorna a lista canônica
  # carregada de api/config/class_choices/<id>.yml por ClassChoicesCatalog.
  #
  # Response:
  #   {
  #     "catalog": "metamagic",
  #     "entries": [
  #       { "slug": "mm-careful", "name_pt": "Magia Cuidadosa", "name_en": "...",
  #         "description": "...", "mechanical_summary": "...", "cost": 1,
  #         "classes": ["sorcerer"], "aliases": ["Suturar Magia"], "prereqs": {} },
  #       ...
  #     ]
  #   }
  #
  # 404 se o catálogo não existir, 422 se schema inválido.
  def show
    catalog = params[:id].to_s
    unless catalog =~ /\A[a-z_][a-z0-9_]*\z/
      return render json: { error: 'invalid catalog name' }, status: :unprocessable_entity
    end

    entries = ClassChoicesCatalog.load(catalog.to_sym)
    render json: { catalog: catalog, entries: entries }, status: :ok
  rescue ClassChoicesCatalog::SchemaError => e
    if e.message =~ /não encontrado/i
      render json: { error: e.message }, status: :not_found
    else
      Rails.logger.error "ClassChoicesController.show schema_error: #{e.message}"
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
end
