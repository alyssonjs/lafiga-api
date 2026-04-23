class Api::V1::Player::SheetItemsController < ApplicationController
  before_action :authorize_request
  before_action :ensure_ownership_by_sheet, only: [:index, :create]
  before_action :ensure_ownership_by_item, only: [:update, :destroy]
  before_action :ensure_ownership_by_item_for_member, only: [:equip, :unequip]

  # GET /api/v1/player/sheet_items?sheet_id=ID
  def index
    items = SheetItem.where(sheet_id: params[:sheet_id])
    render json: { sheet_items: items.map(&:as_inventory_json) }, status: :ok
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/player/sheet_items
  # body: { sheet_item: { sheet_id, item_index?, item_name, category?, quantity?, equipped?, slot?, source?, props_json? } }
  def create
    item = SheetItem.new(item_params)
    if item.save
      render json: { sheet_item: item.as_inventory_json }, status: :created
    else
      render json: { errors: item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PUT /api/v1/player/sheet_items/:id
  def update
    if @item.update(item_params)
      render json: { sheet_item: @item.as_inventory_json }, status: :ok
    else
      render json: { errors: @item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/player/sheet_items/:id
  def destroy
    @item.destroy
    head :no_content
  end

  # POST /api/v1/player/sheet_items/:id/equip
  # body: { slot: <SheetItem::ALL_SLOTS>, props_json?: { using_two_hands?: boolean } }
  def equip
    slot = params[:slot].to_s
    unless SheetItem::ALL_SLOTS.include?(slot)
      return render json: { error: "Invalid slot. Allowed: #{SheetItem::ALL_SLOTS.join(', ')}" }, status: :unprocessable_entity
    end

    SheetItem.transaction do
      pj = params[:props_json].is_a?(ActionController::Parameters) ? params[:props_json].to_unsafe_h : params[:props_json]
      merged = (@item.props_json || {}).merge(pj || {})
      @item.update!(equipped: true, slot: slot, props_json: merged)
    end
    render json: { sheet_item: @item.as_inventory_json }, status: :ok
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/player/sheet_items/:id/unequip
  def unequip
    @item.update(equipped: false, slot: nil)
    render json: { sheet_item: @item.as_inventory_json }, status: :ok
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def item_params
    params.require(:sheet_item).permit(:sheet_id, :item_index, :item_name, :category, :quantity, :equipped, :slot, :source, :notes, props_json: {})
  end

  def ensure_ownership_by_sheet
    sheet_id = params[:sheet_id].presence || params.dig(:sheet_item, :sheet_id)
    sheet = Sheet.find(sheet_id)
    return if Group.user_is_dm?(@current_user)
    return if sheet.character.user_id == @current_user.id

    render json: { error: 'Forbidden' }, status: :forbidden
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end

  def ensure_ownership_by_item
    @item = SheetItem.find(params[:id])
    return if Group.user_is_dm?(@current_user)
    return if @item.sheet.character.user_id == @current_user.id

    render json: { error: 'Forbidden' }, status: :forbidden
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end

  def ensure_ownership_by_item_for_member
    @item = SheetItem.find(params[:id])
    return if Group.user_is_dm?(@current_user)
    return if @item.sheet.character.user_id == @current_user.id

    render json: { error: 'Forbidden' }, status: :forbidden
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end
end
