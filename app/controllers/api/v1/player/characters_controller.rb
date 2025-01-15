class Api::V1::Player::CharactersController < ApplicationController
  before_action :authorize_request
  before_action :get_character, only: [:show, :update, :destroy]

  def index
    characters = @current_user.characters
    render json: {characters: characters}, status: 200 
  end

  def show
    #only returns if the character id is from the current user (function get_character)
    render json: {character: @character}, status: 200
  end

  def create
    params = character_params.merge(user_id: @current_user.id)
    character = Character.new(params)
    if character.save
      render json: {character: character}, status: 200
    else
      render json: { errors: character.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: {errors: e.message}, status: 422
  end

  def update
    #only updates if the character id is from the current user (function get_character)
    if @character.update(character_params)
      render json: {character: @character}, status: 200
    else
      render json: { errors: @character.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: {errors: e.message}
  end

  def destroy
    @character.destroy
    render json: {message: "Deletado com sucesso"}, status: 200
  rescue StandardError => e
    render json: {errors: e.message} 
  end

  private

  def character_params
    params.permit(
      :name, :background, :group_id
    )
  end

  def get_character
    @character =  @current_user.characters.find(params[:id])
  rescue StandardError => e 
    render json: { errors: e.message }, status: :not_found
  end
end

