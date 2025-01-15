class Api::V1::Admin::SubRacesController < ApplicationController
  before_action :authorize_admin_request
  before_action :set_sub_race, only: [:show, :update, :destroy]

  def index
    sub_races = SubRace.all
    render json: {sub_races: sub_races}, status: 200
  end

  def show
    render json: {sub_race: @sub_race}, status: 200
  end

  def create
    @sub_race = SubRace.new(sub_race_params)
    
    if @sub_race.save
      render json: @sub_race, status: :created
    else
      render json: { errors: @sub_race.errors.full_messages }, status: :unprocessable_entity
    end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    if @sub_race.update(sub_race_params)
      render json: {sub_races: @sub_race}, status: 200 
    else
      render json: { errors: @sub_race.errors.full_messages }, status: :unprocessable_entity
    end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity   
  end

  def destroy
    @sub_race.destroy
    render json: {message: "Deletado com sucesso"}, status: 200
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end

  private

  def set_sub_race
    @sub_race = SubRace.find(params[:id])
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end

  def sub_race_params
    params.require(:sub_race).permit(:name, :race_id)
  end
end