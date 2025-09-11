class Api::V1::Public::CharactersController < ApplicationController
  before_action :get_character, only: [:show]

  def index
    # Simple pagination (no gem): limit/offset with meta
    scope = Character.includes(sheet: [:race, :sub_race, :klasses, :sub_klasses]).order(created_at: :desc)
    page = params.fetch(:page, 1).to_i
    per_page = [[params.fetch(:per_page, 25).to_i, 100].min, 1].max
    characters = scope.limit(per_page).offset((page - 1) * per_page)

    includes = { sheet: { include: [:race, :sub_race, :klasses, :sub_klasses] } }

    render json: {
      characters: characters.as_json(include: includes),
      meta: { page: page, per_page: per_page, total: scope.count }
    }, status: :ok
  end

  def show
    includes = { sheet: { include: [:race, :sub_race, :klasses, :sub_klasses] } }
    render json: { character: @character.as_json(include: includes) }, status: :ok
  end

  private

  def get_character
    @character = Character.includes(sheet: [:race, :sub_race, :klasses, :sub_klasses]).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Character not found' }, status: :not_found
  end
end
