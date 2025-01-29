class Api::V1::Player::SheetKlassesController < ApplicationController
  before_action :authorize_request
  before_action :set_sheet_klass, only: [:show, :update, :destroy]

  def index
    sheet_klasses = @current_user.sheet_klasses
    render json: {sheet_klasses: sheet_klasses}, status: 200
  end
  
  def show
    render json: {sheet_klass: @sheet_klass}, status: 200
  end

  def create
    @sheet_klass = SheetKlass.new(sheet_klass_params)
    
    if @sheet_klass.save
      render json: @sheet_klass, status: :created
    else
      render json: { errors: @sheet_klass.errors.full_messages }, status: :unprocessable_entity
    end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    if @sheet_klass.update(sheet_klass_params)
      render json: {sheet_klass: @sheet_klass}, status: 200 
    else
      render json: { errors: @sheet_klass.errors.full_messages }, status: :unprocessable_entity
    end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity   
  end

  def destroy
    @sheet_klass.destroy
    render json: {message: "Deletado com sucesso"}, status: 200
  rescue StandardError=> e
    render json: { error: e.message }, status: :not_found
  end

  private

  def set_sheet_klass
    @sheet_klass = @current_user.sheet_klasses.find(params[:id])
  rescue StandardError=> e
    render json: { error: e.message }, status: :not_found
  end

  def sheet_klass_params
    params.require(:sheet_klass).permit(:sheet_id, :klass_id, :sub_klass_id, :level)
  end
end