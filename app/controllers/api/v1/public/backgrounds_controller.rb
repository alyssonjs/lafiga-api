class Api::V1::Public::BackgroundsController < ApplicationController
  # GET /api/v1/public/backgrounds
  def index
    render json: { backgrounds: BackgroundRules.all }, status: :ok
  end

  # GET /api/v1/public/backgrounds/:id
  def show
    bg = BackgroundRules.find(params[:id])
    return render json: { error: 'not found' }, status: :not_found unless bg
    render json: { background: bg }, status: :ok
  end

  # POST /api/v1/public/backgrounds/apply
  # body: { selection: { key, choices: { languages:[], gaming_set:[] } } }
  def apply
    selection = params.require(:selection).permit!
    result = BackgroundRules.apply(selection.to_h.symbolize_keys)
    render json: { result: result }, status: :ok
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end

