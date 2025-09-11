class Api::V1::Public::SubKlassesController < ApplicationController
  before_action :set_sub_klass, only: [:show]
  before_action :set_sub_klass_for_levels, only: [:levels]

  def index
    sub_klasses = SubKlass.all

    render json: {sub_klasses: sub_klasses}, status: 200
  end

  def show
    render json: {sub_klass: @sub_klass}, status: 200
  end

  def levels
    levels = @sub_klass.sub_klass_levels
    render json: { sub_klass_levels: levels.as_json(include: [:features]) }, status: :ok
  end

  private

  def set_sub_klass
    @sub_klass = SubKlass.find(params[:id])
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end

  def set_sub_klass_for_levels
    @sub_klass = SubKlass.find(params[:id])
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end
end
