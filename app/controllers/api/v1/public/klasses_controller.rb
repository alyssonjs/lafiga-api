class Api::V1::Public::KlassesController < ApplicationController
  before_action :set_klass, only: [:show, :levels]

  def index
    klasses = Klass.all
    render json: {klasses: klasses}, status: 200
  end
  
  def show
    render json: {klass: @klass}, status: 200
  end

  def levels
    levels = @klass.class_levels
    render json: { class_levels: levels.as_json(include: [:spellcasting, :features]) }, status: :ok
  end

  private

  def set_klass
    @klass = Klass.find(params[:id])
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end
end
