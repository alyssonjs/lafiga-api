class Api::V1::Public::SpellsController < ApplicationController
  def index
    spells = Spell.all
    if params[:ids].present?
      ids = Array(params[:ids]).map(&:to_i).reject(&:zero?)
      spells = spells.where(id: ids) if ids.any?
    end
    if params[:klass_id].present?
      klass_id = params[:klass_id].to_i
      ids = SpellSource.where(source_type: 'Klass', source_id: klass_id).pluck(:spell_id)
      spells = spells.where(id: ids)
    end

    render json: { spells: spells }, status: :ok
  end

  def show
    spell = Spell.find(params[:id])
    render json: { spell: spell }, status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Spell not found' }, status: :not_found
  end
end
