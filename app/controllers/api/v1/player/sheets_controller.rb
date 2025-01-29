class Api::V1::Player::SheetsController < ApplicationController
  before_action :authorize_request
  before_action :set_sheet, only: [:show, :update, :destroy]

  def index
    sheets = @current_user.sheets
    render json: {sheets: sheets}, status: 200
  end
  
  def show
    render json: {sheet: @sheet}, status: 200
  end

  def create
    @sheet = Sheet.new(sheet_params)
    
    if @sheet.save
      render json: @sheet, status: :created
    else
      render json: { errors: @sheet.errors.full_messages }, status: :unprocessable_entity
    end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    if @sheet.update(sheet_params)
      render json: {sheet: @sheet}, status: 200 
    else
      render json: { errors: @sheet.errors.full_messages }, status: :unprocessable_entity
    end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity   
  end

  def destroy
    @sheet.destroy
    render json: {message: "Deletado com sucesso"}, status: 200
  rescue StandardError=> e
    render json: { error: e.message }, status: :not_found
  end

  private

  def set_sheet
    @sheet = @current_user.sheets.find(params[:id])
  rescue StandardError=> e
    render json: { error: e.message }, status: :not_found
  end

  def sheet_params
    params.require(:sheet).permit(:character_id, :race_id, :sub_race_id)
  end
end