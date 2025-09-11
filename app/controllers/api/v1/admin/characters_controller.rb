class Api::V1::Admin::CharactersController < ApplicationController
  before_action :authorize_admin_request
  before_action :get_character, only: [:show, :update, :destroy]

  def index
    scope = Character.order(created_at: :desc)
    page = params.fetch(:page, 1).to_i
    per_page = [[params.fetch(:per_page, 25).to_i, 100].min, 1].max
    characters = scope.limit(per_page).offset((page - 1) * per_page)

    render json: {
      characters: characters,
      meta: { page: page, per_page: per_page, total: scope.count }
    }, status: :ok
  end

  def show
    render json: { character: @character }, status: :ok
  end

  def create
    character = Character.new(character_params)
    if character.save
      render json: { character: character }, status: :created
    else
      render json: { errors: character.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @character.update(character_params)
      render json: { character: @character }, status: :ok
    else
      render json: { errors: @character.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @character.destroy
    head :no_content
  end

  private

  def character_params
    params.require(:character).permit(
      :name, :background, :user_id, :group_id
    )
  end

  def get_character
    @character = Character.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { errors: 'Character not found' }, status: :not_found
  end
end
