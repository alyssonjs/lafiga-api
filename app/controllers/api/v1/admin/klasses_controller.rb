class Api::V1::Admin::KlassesController < ApplicationController
  before_action :authorize_admin_request
  before_action :set_klass, only: [:show, :update, :destroy]

  def index
    klasses = Klass.all
    render json: {klasses: klasses}, status: 200
  end
  
  def show
    render json: {klass: @klass}, status: 200
  end

  def create
    @klass = Klass.new(klass_params)
    
    if @klass.save
      render json: @klass, status: :created
    else
      render json: { errors: @klass.errors.full_messages }, status: :unprocessable_entity
    end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    if @klass.update(klass_params)
      render json: {klass: @klass}, status: 200 
    else
      render json: { errors: @klass.errors.full_messages }, status: :unprocessable_entity
    end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity   
  end

  def destroy
    @klass.destroy
    render json: {message: "Deletado com sucesso"}, status: 200
  rescue StandardError=> e
    render json: { error: e.message }, status: :not_found
  end

  private

  def set_klass
    @klass = Klass.find(params[:id])
  rescue StandardError=> e
    render json: { error: e.message }, status: :not_found
  end

  def klass_params
    params.require(:klass).permit(:name)
  end
end