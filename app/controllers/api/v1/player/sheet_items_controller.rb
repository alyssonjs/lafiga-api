class Api::V1::Player::SheetItemsController < ApplicationController
  before_action :authorize_request
  before_action :ensure_ownership_by_sheet, only: [:index, :create, :reorder]
  before_action :ensure_ownership_by_item, only: [:update, :destroy]
  before_action :ensure_ownership_by_item_for_member, only: [:equip, :unequip, :allocate_ammunition, :merge, :split]

  # GET /api/v1/player/sheet_items?sheet_id=ID
  def index
    # `includes(:item)` pré-carrega a associação belongs_to :item numa única
    # query IN(...) — sem isto, `as_inventory_json` → `weapon_props` disparava 1
    # SELECT por linha ao tocar `item.item` (N+1). Espelha EquipmentProfileService.
    items = SheetItem.includes(:item).where(sheet_id: params[:sheet_id]).order(:position, :id)
    render json: { sheet_items: items.map(&:as_inventory_json) }, status: :ok
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/player/sheet_items
  # body: { sheet_item: { sheet_id, item_index?, item_name, category?, quantity?, equipped?, slot?, source?, props_json? } }
  def create
    item = SheetItem.new(item_params)
    record, created = SheetItem.stack_or_create!(item)
    broadcast_inventory_changed(record)
    render json: { sheet_item: record.as_inventory_json }, status: (created ? :created : :ok)
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # PUT /api/v1/player/sheet_items/:id
  def update
    if @item.update(item_params)
      broadcast_inventory_changed(@item)
      render json: { sheet_item: @item.as_inventory_json }, status: :ok
    else
      render json: { errors: @item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/player/sheet_items/:id
  def destroy
    item = @item
    @item.destroy
    broadcast_inventory_changed(item)
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
    broadcast_inventory_changed(@item)
    render json: { sheet_item: @item.as_inventory_json }, status: :ok
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/player/sheet_items/:id/unequip
  def unequip
    @item.update(equipped: false, slot: nil)
    broadcast_inventory_changed(@item)
    render json: { sheet_item: @item.as_inventory_json }, status: :ok
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/player/sheet_items/:id/allocate_ammunition
  # body: { quiver_id: SheetItem id | null, quantity: integer }
  def allocate_ammunition
    items = SheetItems::AllocateAmmunitionService.new(
      ammunition: @item,
      quiver_id: params[:quiver_id],
      quantity: params[:quantity]
    ).call
    broadcast_inventory_changed(@item)
    render json: { sheet_items: items }, status: :ok
  rescue SheetItems::AllocateAmmunitionService::InvalidAllocation => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # POST /api/v1/player/sheet_items/reorder
  # body: { sheet_id, ordered_ids: [id, id, ...] }
  def reorder
    sheet = Sheet.find(params[:sheet_id])
    items = SheetItems::ReorderService.new(sheet: sheet, ordered_ids: params[:ordered_ids]).call
    broadcast_inventory_changed(sheet)
    render json: { sheet_items: items }, status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  rescue SheetItems::ReorderService::InvalidReorder => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/player/sheet_items/:id/merge
  # body: { target_id } — soma esta pilha (:id) NA pilha destino e destrói a origem.
  def merge
    items = SheetItems::MergeStacksService.new(
      sheet: @item.sheet,
      source_id: @item.id,
      target_id: params[:target_id]
    ).call
    broadcast_inventory_changed(@item.sheet)
    render json: { sheet_items: items }, status: :ok
  rescue SheetItems::MergeStacksService::InvalidMerge => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/player/sheet_items/:id/split
  # body: { quantity } — separa N unidades desta pilha numa nova pilha.
  def split
    items = SheetItems::SplitStackService.new(item: @item, quantity: params[:quantity]).call
    broadcast_inventory_changed(@item.sheet)
    render json: { sheet_items: items }, status: :ok
  rescue SheetItems::SplitStackService::InvalidSplit => e
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

  def broadcast_inventory_changed(item_or_sheet)
    map = BattleMap.find_by(id: params[:battle_map_id])
    return unless map&.readable_by?(@current_user)

    # Marca a mesa na instância: a sincronia do equipamento e o broadcast ficam
    # na sessão certa. Sem `schedule_id`, cai no comportamento antigo (mapa).
    map.session_scope_schedule_id = session_scope_for(map)

    sheet = item_or_sheet.is_a?(Sheet) ? item_or_sheet : item_or_sheet.sheet
    character = sheet&.character
    return unless character

    changes = BattleMapTokenEquipment.sync!(map: map, character: character)
    changes.each do |changed|
      MapRealtime::Broadcaster.token_equipment_changed(
        map,
        changed[:token_id],
        changed[:chibi_equipment],
        actor: @current_user,
      )
    end

    MapRealtime::Broadcaster.character_inventory_changed(
      map,
      character.id,
      sheet.id,
      actor: @current_user,
    )
  rescue StandardError => e
    Rails.logger.warn({ event: 'sheet_items.broadcast_inventory_failed', error: e.class.name, message: e.message }.to_json)
  end

  # `schedule_id` do request, só se o utilizador puder ver a sessão E ela usar
  # este mapa — o mesmo critério do BattleMapsController.
  def session_scope_for(map)
    sid = params[:schedule_id].presence
    return nil unless sid

    schedule = Schedule.find_by(id: sid)
    return nil unless schedule&.viewable_by?(@current_user)
    return nil unless schedule.battle_map_id == map.id ||
                      ScheduleBattleMap.exists?(schedule_id: schedule.id, battle_map_id: map.id)

    schedule.id
  end

end
