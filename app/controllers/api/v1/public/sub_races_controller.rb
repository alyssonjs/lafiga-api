class Api::V1::Public::SubRacesController < ApplicationController
  before_action :set_sub_race, only: [:show]

  def index
    sub_races = SubRace.all

    render json: {sub_races: sub_races}, status: 200
  end

  def show
    render json: {sub_race: @sub_race}, status: 200
  end

  private

  def set_sub_race
    @sub_race = SubRace.find(params[:id])
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end
end