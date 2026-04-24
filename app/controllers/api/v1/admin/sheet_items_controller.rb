class Api::V1::Admin::SheetItemsController < ApplicationController
  # Mestre (papel DM) — mesmo critério que `SheetsController#summary` e
  # `Group.user_is_dm?`. `authorize_admin_request` só permitia `role: Admin`
  # literal e dava 401 em prod para contas "Mestre" da plataforma.
  before_action :authorize_site_wide_dm
  before_action :set_item, only: [:update, :destroy, :equip, :unequip]

  # GET /api/v1/admin/sheet_items?sheet_id=ID
  def index
    items = params[:sheet_id].present? ? SheetItem.where(sheet_id: params[:sheet_id]) : SheetItem.all.limit(200)
    render json: { sheet_items: items.map(&:as_inventory_json) }, status: :ok
  end

  # POST /api/v1/admin/sheet_items
  def create
    item = SheetItem.new(item_params)
    if item.save
      render json: { sheet_item: item.as_inventory_json }, status: :created
    else
      render json: { errors: item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PUT /api/v1/admin/sheet_items/:id
  def update
    if @item.update(item_params)
      render json: { sheet_item: @item.as_inventory_json }, status: :ok
    else
      render json: { errors: @item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/admin/sheet_items/:id
  def destroy
    @item.destroy
    head :no_content
  end

  # POST /api/v1/admin/sheet_items/:id/equip
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

  # POST /api/v1/admin/sheet_items/:id/unequip
  def unequip
    @item.update(equipped: false, slot: nil)
    render json: { sheet_item: @item.as_inventory_json }, status: :ok
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/admin/sheet_items/grant
  # body: { grant: { sheet_id, item_index?, item_name, category?, quantity?, props_json?, notes? } }
  # Endpoint dedicado para o DM conceder itens em sessão. Sempre marca
  # `source: 'dm_grant'` para auditoria. Se já existir um SheetItem na sheet
  # com o mesmo `item_index` (catálogo), incrementa a quantidade em vez de
  # duplicar. Itens sem `item_index` (custom) sempre criam linha nova.
  def grant
    raw = params.require(:grant).permit(:sheet_id, :item_index, :item_name, :category, :quantity, :notes, props_json: {})
    sheet = Sheet.find(raw[:sheet_id])
    qty = [raw[:quantity].to_i, 1].max

    item = nil
    SheetItem.transaction do
      if raw[:item_index].present?
        existing = SheetItem.where(sheet_id: sheet.id, item_index: raw[:item_index], source: 'dm_grant').order(:id).first
        if existing
          existing.update!(quantity: existing.quantity + qty)
          item = existing
        end
      end

      if item.nil?
        item = SheetItem.create!(
          sheet_id: sheet.id,
          item_index: raw[:item_index],
          item_name: raw[:item_name],
          category: raw[:category],
          quantity: qty,
          equipped: false,
          slot: nil,
          source: 'dm_grant',
          props_json: raw[:props_json].is_a?(ActionController::Parameters) ? raw[:props_json].to_unsafe_h : raw[:props_json],
          notes: raw[:notes],
        )
      end
    end

    render json: { sheet_item: item.as_inventory_json }, status: :created
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Sheet not found' }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_item
    @item = SheetItem.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end

  def item_params
    params.require(:sheet_item).permit(:sheet_id, :item_index, :item_name, :category, :quantity, :equipped, :slot, :source, :notes, props_json: {})
  end
end
