class Api::V1::Public::SkillsController < ApplicationController
  # GET /api/v1/public/skills
  #
  # Catálogo canônico das 18 perícias do PHB 5e (PT-BR). Single source of
  # truth — FRONT deve consumir este endpoint em vez de manter
  # `ABILITY_BLOCKS` hardcoded em `character-creation/types.ts`.
  #
  # Resposta:
  #   { "skills": [{ id, name, ability }], "meta": { total, source } }
  #
  # Audit que protege a fonte: `spec/services/skills_canonical_consistency_audit_spec.rb`.
  def index
    skills = SkillsCatalog.all.map do |s|
      { id: s[:id].to_s, name: s[:name].to_s, ability: s[:ability].to_s }
    end
    render json: {
      skills: skills,
      meta: { total: skills.length, source: 'config/skills.yml' }
    }, status: :ok
  end

  # GET /api/v1/public/skills/:id
  #
  # `:id` aceita slug (`athletics`) OU nome canônico PT-BR (case-insensitive,
  # ex.: `Atletismo` ou `atletismo`).
  def show
    skill = SkillsCatalog.find(params[:id])
    return render json: { error: 'skill not found' }, status: :not_found unless skill

    render json: {
      skill: { id: skill[:id].to_s, name: skill[:name].to_s, ability: skill[:ability].to_s }
    }, status: :ok
  end
end

