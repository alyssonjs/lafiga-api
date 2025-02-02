class Api::V1::Admin::RacesController < ApplicationController
  before_action :authorize_admin_request
  before_action :set_race, only: [:show, :update, :destroy]


  def index
    races = Race.all
    render json: {races: races}, status: 200
  end
  
  def show
    render json: {race: @race}, status: 200
  end

  def create
    @race = Race.new(race_params)
    
    if @race.save
      render json: @race, status: :created
    else
      render json: { errors: @race.errors.full_messages }, status: :unprocessable_entity
    end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    if @race.update(race_params)
      render json: {race: @race}, status: 200 
    else
      render json: { errors: @race.errors.full_messages }, status: :unprocessable_entity
    end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity   
  end

  def destroy
    @race.destroy
    render json: {message: "Deletado com sucesso"}, status: 200
  rescue StandardError=> e
    render json: { error: e.message }, status: :not_found
  end

  private

  def set_race
    @race = Race.find(params[:id])
  rescue StandardError=> e
    render json: { error: e.message }, status: :not_found
  end

  def race_params
    params.require(:race).permit(:name)
  end
end