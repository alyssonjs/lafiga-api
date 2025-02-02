class Api::V1::Public::RacesController < ApplicationController
  before_action :set_race, only: [:show]

  def index
    races = Race.all
    render json: {races: races}, status: 200
  end
  
  def show
    render json: {race: @race}, status: 200
  end

  private

  def set_race
    @race = Race.find(params[:id])
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end
end