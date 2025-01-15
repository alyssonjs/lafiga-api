class Api::V1::Admin::CharactersController < ApplicationController
    before_action :authorize_admin_request
    before_action :get_character, only: [:show, :update, :destroy]
  
    def index
      #TODO  change all to pagination
      characters = Character.all
      render json: {characters: characters}, status: 200 
    end
  
    def show
      render json: {character: @character}, status: 200
    end
  
    def create
      character = Character.new(character_params)
      if character.save
        render json: {character: character}, status: 200
      else
        render json: { errors: character.errors.full_messages }, status: :unprocessable_entity
      end
    rescue StandardError => e
      render json: {errors: e.message}, status: 422 
    end
  
    def update
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
        :name, :background, :user_id, :group_id
      )
    end
  
    def get_character
      @character = Character.find(params[:id])
    rescue StandardError => e 
      render json: { errors: e.message }, status: :not_found
    end
end
