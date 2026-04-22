class Api::V1::Public::RacesController < ApplicationController
  before_action :set_race, only: [:show]

  def index
    races = Race.includes(:sub_races).all
    render json: {
      races: races.map { |r|
        {
          id: r.id,
          name: r.name,
          api_index: (r.api_index.presence || (r.name || '').to_s.parameterize(separator: '_')),
          sub_races: r.sub_races.map { |sr| { id: sr.id, name: sr.name, race_id: r.id, api_index: (sr.api_index.presence || (sr.name || '').to_s.parameterize(separator: '_')) } }
        }
      }
    }, status: 200
  end
  
  def show
    api_index = (@race.api_index.presence || (@race.name || '').to_s.parameterize(separator: '_'))
    render json: {
      race: {
        id: @race.id,
        name: @race.name,
        api_index: api_index
      }
    }, status: 200
  end

  private

  def set_race
    @race = Race.find(params[:id])
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end
end
