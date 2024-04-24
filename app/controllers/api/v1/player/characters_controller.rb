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
    
    begin
      params = character_params.merge(user_id: @current_user.id)
      character = Character.new(params)
      character.save!
    rescue ActiveRecord::RecordInvalid
      render json: {errors: character.errors}, status: 422 
      return
    end
    
    render json: {character: character}, status: 200
   
  end

  def update
    #only updates if the character id is from the current user (function get_character)
    unless @character.update(character_params)
      render json: {errors: character.errors}
    end
    render json: {character: @character}, status: 200
  end

  def destroy
    unless @character.destroy
      render json: {errors: character.errors}
    end
    render json: {message: "Deletado com sucesso"}, status: 200
  end

  private

  def character_params
    params.permit(
      :name, :background
    )
  end

  def get_character
    begin
        @character =  @current_user.characters.find(params[:id])
    rescue ActiveRecord::RecordNotFound => exception 
        render json: { errors: exception }, status: :not_found
    end
  end

end

