class Api::V1::Public::SkillsController < ApplicationController
  # GET /api/v1/public/skills
  # Retorna todas as perícias com id (inglês) e name (português)
  def index
    render json: { skills: SkillsCatalog.all }, status: :ok
  end

  # GET /api/v1/public/skills/:id
  # Retorna uma perícia específica
  def show
    skill = SkillsCatalog.find(params[:id])
    if skill
      render json: { skill: skill }, status: :ok
    else
      render json: { error: 'Skill not found' }, status: :not_found
    end
  end
end

