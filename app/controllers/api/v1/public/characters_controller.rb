class Api::V1::Public::CharactersController < ApplicationController
    before_action :get_character, only: [:show]

    def index
        #TODO change to pagination
        characters = Character.all
        render json: {characters: characters}, status: 200 
    end

    def show
        render json: {character: @character}, status: 200
    end

    private

    def get_character
        @character = Character.find(params[:id])
    rescue ActiveRecord::RecordNotFound => e
        render json: { error: e.message }, status: :not_found
    end
end
