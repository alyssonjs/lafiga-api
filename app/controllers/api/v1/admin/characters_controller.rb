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
      
      begin
        character = Character.new(character_params)
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
        :name, :background, :user_id
      )
    end
  
    def get_character
      begin
          @character = Character.find(params[:id])
      rescue ActiveRecord::RecordNotFound => exception 
          render json: { errors: exception }, status: :not_found
      end
    end
  
end
