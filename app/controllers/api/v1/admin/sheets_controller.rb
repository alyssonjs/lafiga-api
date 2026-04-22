class Api::V1::Admin::SheetsController < ApplicationController
  # `summary` is read-only and must work for mestres (papel "DM"), nao so
  # "Admin" literal — mesmo criterio de Group.user_is_dm? / grupos.
  before_action :authorize_admin_request, except: [:summary]
  before_action :authorize_site_wide_dm, only: [:summary]
  before_action :set_sheet, only: [:show, :update, :destroy]

  def index
    sheets = Sheet.all
    render json: {sheets: sheets}, status: 200
  end
  
  def show
    render json: {sheet: @sheet}, status: 200
  end

  # GET /api/v1/admin/sheets/:id/summary — CharacterSheetSummaryService para
  # qualquer ficha (mestre visualiza PC de outro jogador; player/sheets nao).
  def summary
    sheet = Sheet.find(params[:id])
    service = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: (params[:sync] != 'false'))
    if service.success?
      render json: {summary: service.result}, status: :ok
    else
      render json: {errors: service.errors.full_messages}, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: {error: 'not_found'}, status: :not_found
  rescue StandardError => e
    render json: {error: e.message}, status: :unprocessable_entity
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
    @sheet = Sheet.find(params[:id])
  rescue StandardError=> e
    render json: { error: e.message }, status: :not_found
  end

  def sheet_params
    params.require(:sheet).permit(
      :character_id,
      :race_id,
      :sub_race_id,
      :str, :dex, :con, :int, :wis, :cha,
      :hp_max, :hp_current, :temp_hp,
      :metadata
    )
  end
end
