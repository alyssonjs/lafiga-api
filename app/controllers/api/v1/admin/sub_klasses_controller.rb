class Api::V1::Admin::SubKlassesController < ApplicationController
  before_action :authorize_admin_request
  before_action :set_sub_klass, only: [:show, :update, :destroy]

  def index
    sub_klasses = SubKlass.all
    render json: {sub_klasses: sub_klasses}, status: 200
  end

  def show
    render json: {sub_klass: @sub_klass}, status: 200
  end

  def create
    @sub_klass = SubKlass.new(sub_klass_params)
    
    if @sub_klass.save
      render json: @sub_klass, status: :created
    else
      render json: { errors: @sub_klass.errors.full_messages }, status: :unprocessable_entity
    end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    if @sub_klass.update(sub_klass_params)
      render json: {sub_klass: @sub_klass}, status: 200 
    else
      render json: { errors: @sub_klass.errors.full_messages }, status: :unprocessable_entity
    end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity   
  end

  def destroy
    @sub_klass.destroy
    render json: {message: "Deletado com sucesso"}, status: 200
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end

  private

  def set_sub_klass
    @sub_klass = SubKlass.find(params[:id])
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end

  def sub_klass_params
    params.require(:sub_klass).permit(:name, :klass_id)
  end
end