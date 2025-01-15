class Api::V1::Public::SubKlassesController < ApplicationController
  before_action :set_sub_klass, only: [:show]

  def index
    sub_klasses = SubKlass.all

    render json: {sub_klasses: sub_klasses}, status: 200
  end

  def show
    render json: {sub_klass: @sub_klass}, status: 200
  end

  private

  def set_sub_klass
    @sub_klass = SubKlass.find(params[:id])
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end
end