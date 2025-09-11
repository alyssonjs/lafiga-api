class Api::V1::Player::SheetItemsController < ApplicationController
  before_action :authorize_request
  before_action :ensure_ownership_by_sheet, only: [:index, :create]
  before_action :ensure_ownership_by_item, only: [:update, :destroy]

  # GET /api/v1/player/sheet_items?sheet_id=ID
  def index
    items = SheetItem.where(sheet_id: params[:sheet_id])
    render json: { sheet_items: items }, status: :ok
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/player/sheet_items
  # body: { sheet_item: { sheet_id, item_index?, item_name, category?, quantity?, equipped?, slot?, source?, props_json? } }
  def create
    item = SheetItem.new(item_params)
    if item.save
      render json: { sheet_item: item }, status: :created
    else
      render json: { errors: item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PUT /api/v1/player/sheet_items/:id
  def update
    if @item.update(item_params)
      render json: { sheet_item: @item }, status: :ok
    else
      render json: { errors: @item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/player/sheet_items/:id
  def destroy
    @item.destroy
    head :no_content
  end

  private

  def item_params
    params.require(:sheet_item).permit(:sheet_id, :item_index, :item_name, :category, :quantity, :equipped, :slot, :source, props_json: {})
  end

  def ensure_ownership_by_sheet
    sheet = Sheet.find(params[:sheet_id] || params.dig(:sheet_item, :sheet_id))
    raise StandardError, 'Forbidden' unless sheet.character.user_id == @current_user.id
  end

  def ensure_ownership_by_item
    @item = SheetItem.find(params[:id])
    raise StandardError, 'Forbidden' unless @item.sheet.character.user_id == @current_user.id
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end
end

