class Api::V1::Public::SubRacesController < ApplicationController
  before_action :set_sub_race, only: [:show]

  def index
    sub_races = SubRace.all
    render json: {
      sub_races: sub_races.map { |sr|
        { id: sr.id, name: sr.name, race_id: sr.race_id, api_index: (sr.api_index.presence || (sr.name || '').to_s.parameterize(separator: '_')) }
      }
    }, status: 200
  end

  def show
    render json: {
      sub_race: { id: @sub_race.id, name: @sub_race.name, race_id: @sub_race.race_id, api_index: (@sub_race.api_index.presence || (@sub_race.name || '').to_s.parameterize(separator: '_')) }
    }, status: 200
  end

  private

  def set_sub_race
    @sub_race = SubRace.find(params[:id])
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end
end
