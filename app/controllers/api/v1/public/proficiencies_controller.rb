class Api::V1::Public::ProficienciesController < ApplicationController
  # GET /api/v1/public/proficiencies?category=language
  #
  # Catálogo canônico de proficiências. FASE 1 — por enquanto só `language`
  # está semeado (ver `.cursor/dnd-rules/proficiencias-levantamento.md`).
  #
  # Existe para que o FRONT consuma em vez de redeclarar. Havia três listas
  # rivais de idioma — o catálogo do front, `config/race_rules.yml` e
  # `background_rules.rb` — e o próprio cabeçalho de `languageCatalog.ts`
  # registrava que nunca tinham sido reconciliadas.
  #
  # Resposta:
  #   { "proficiencies": [{ api_index, name, category, sub_category,
  #                         metadata, source, aliases: [...] }],
  #     "meta": { total, categories: {...} } }
  def index
    escopo = Proficiency.published.includes(:proficiency_aliases, :proficiency_sources).order(:category, :sub_category, :name)
    escopo = escopo.of(params[:category]) if params[:category].present?

    linhas = escopo.map do |p|
      {
        api_index: p.api_index,
        name: p.name,
        category: p.category,
        sub_category: p.sub_category,
        metadata: p.metadata || {},
        source: p.source,
        # As grafias aceitas viajam junto: sem elas o consumidor teria de
        # reimplementar a resolução, que é como as quatro grafias nasceram.
        aliases: p.proficiency_aliases.map(&:alias_key).sort,
        # Treinamento: horas necessárias para aprender, quando treinável.
        trainable: p.trainable?,
        training_hours: p.training_hours,
        # Quem concede — registro, não autoridade.
        sources: p.proficiency_sources.map { |s|
          { source_type: s.source_type, source_key: s.source_key,
            source_name: s.source_name, label: s.label }
        },
      }
    end

    render json: {
      proficiencies: linhas,
      meta: {
        total: linhas.length,
        categories: linhas.group_by { |l| l[:category] }.transform_values(&:size),
      },
    }, status: :ok
  end
end
