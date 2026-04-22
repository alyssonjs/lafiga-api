class Api::V1::Public::SavingThrowsController < ApplicationController
  # GET /api/v1/public/saving_throws
  # Retorna todas as salvaguardas com id (inglês) e name (português)
  def index
    render json: { saving_throws: SavingThrowsCatalog.all }, status: :ok
  end

  # GET /api/v1/public/saving_throws/:id
  # Retorna uma salvaguarda específica traduzida
  def show
    translated = SavingThrowsCatalog.translate(params[:id])
    if translated
      render json: { id: params[:id], name: translated }, status: :ok
    else
      render json: { error: 'Saving throw not found' }, status: :not_found
    end
  end
end

