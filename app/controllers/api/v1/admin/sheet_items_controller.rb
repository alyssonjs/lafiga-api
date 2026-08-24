class Api::V1::Admin::SheetItemsController < ApplicationController
  # Mestre (papel DM) — mesmo critério que `SheetsController#summary` e
  # `Group.user_is_dm?`. `authorize_admin_request` só permitia `role: Admin`
  # literal e dava 401 em prod para contas "Mestre" da plataforma.
  before_action :authorize_site_wide_dm
  before_action :set_item, only: [:update, :destroy, :equip, :unequip, :attune, :unattune, :allocate_ammunition, :stow_on_mount, :merge, :split, :spend_use]

  # GET /api/v1/admin/sheet_items?sheet_id=ID
  def index
    items = params[:sheet_id].present? ? SheetItem.where(sheet_id: params[:sheet_id]).order(:position, :id) : SheetItem.all.limit(200)
    render json: { sheet_items: items.map(&:as_inventory_json) }, status: :ok
  end

  # POST /api/v1/admin/sheet_items
  def create
    item = SheetItem.new(item_params)
    record, created = SheetItem.stack_or_create!(item)
    broadcast_inventory_changed(record)
    render json: { sheet_item: record.as_inventory_json }, status: (created ? :created : :ok)
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # PUT /api/v1/admin/sheet_items/:id
  def update
    if @item.update(item_params)
      broadcast_inventory_changed(@item)
      render json: { sheet_item: @item.as_inventory_json }, status: :ok
    else
      render json: { errors: @item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/admin/sheet_items/:id
  def destroy
    item = @item
    @item.destroy
    broadcast_inventory_changed(item)
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
    broadcast_inventory_changed(@item)
    render json: { sheet_item: @item.as_inventory_json }, status: :ok
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/admin/sheet_items/:id/unequip
  def unequip
    @item.update(equipped: false, slot: nil)
    broadcast_inventory_changed(@item)
    render json: { sheet_item: @item.as_inventory_json }, status: :ok
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/admin/sheet_items/:id/attune
  #
  # Mesma regra do jogador (teto de 3, ficha travada). O mestre atua sobre a
  # ficha do jogador pelo escopo de DM — corrigir sintonia na mesa e caso real.
  def attune
    SheetItem.transaction do
      sheet = Sheet.lock.find(@item.sheet_id)
      ok, reason = Sheets::Attunement.can_attune?(@item, sheet: sheet)
      raise ActiveRecord::Rollback, reason unless ok

      @item.update!(props_json: (@item.props_json || {}).merge(Sheets::Attunement::PROP_KEY => true))
      @attuned_ok = true
    end

    unless @attuned_ok
      _, reason = Sheets::Attunement.can_attune?(@item)
      return render json: { error: reason || 'Não foi possível sintonizar.' }, status: :unprocessable_entity
    end

    broadcast_inventory_changed(@item)
    render json: { sheet_item: @item.as_inventory_json }, status: :ok
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/admin/sheet_items/:id/unattune
  def unattune
    @item.update!(props_json: (@item.props_json || {}).merge(Sheets::Attunement::PROP_KEY => false))
    broadcast_inventory_changed(@item)
    render json: { sheet_item: @item.as_inventory_json }, status: :ok
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/admin/sheet_items/:id/allocate_ammunition
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

  # POST /api/v1/admin/sheet_items/:id/stow_on_mount
  # O mestre tambem guarda/tira carga da montaria do jogador.
  # POST /api/v1/admin/sheet_items/:id/spend_use — mestre gasta pelo jogador.
  def spend_use
    SheetItems::SpendUseService.new(item: @item, amount: params[:amount] || 1).call
    broadcast_inventory_changed(@item)
    render json: { sheet_item: @item.reload.as_inventory_json }, status: :ok
  rescue SheetItems::SpendUseService::InvalidUse => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def stow_on_mount
    items = SheetItems::StowOnMountService.new(
      item: @item,
      companion_id: params[:companion_id],
      quantity: params[:quantity]
    ).call
    broadcast_inventory_changed(@item)
    render json: { sheet_items: items }, status: :ok
  rescue SheetItems::StowOnMountService::InvalidStow => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
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
        existing = SheetItem.where(sheet_id: sheet.id, item_index: raw[:item_index], source: 'dm_grant').order(:id).lock(true).first
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

    broadcast_inventory_changed(item)

    render json: { sheet_item: item.as_inventory_json }, status: :created
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Sheet not found' }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/admin/sheet_items/reorder
  # body: { sheet_id, ordered_ids: [id, id, ...] }
  def reorder
    sheet = Sheet.find(params[:sheet_id])
    items = SheetItems::ReorderService.new(sheet: sheet, ordered_ids: params[:ordered_ids]).call
    broadcast_inventory_changed(sheet)
    render json: { sheet_items: items }, status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Sheet not found' }, status: :not_found
  rescue SheetItems::ReorderService::InvalidReorder => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/admin/sheet_items/:id/merge
  # body: { target_id }
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

  # POST /api/v1/admin/sheet_items/:id/split
  # body: { quantity }
  def split
    items = SheetItems::SplitStackService.new(item: @item, quantity: params[:quantity]).call
    broadcast_inventory_changed(@item.sheet)
    render json: { sheet_items: items }, status: :ok
  rescue SheetItems::SplitStackService::InvalidSplit => e
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

  def broadcast_inventory_changed(item_or_sheet)
    map_id = params[:battle_map_id].presence || params.dig(:grant, :battle_map_id)
    map = BattleMap.find_by(id: map_id)
    return unless map

    # Marca a mesa na instância (ver BattleMap#session_scope_schedule_id): a
    # sincronia do equipamento e o broadcast ficam na sessão certa.
    sid = params[:schedule_id].presence || params.dig(:grant, :schedule_id).presence
    schedule = sid && Schedule.find_by(id: sid)
    if schedule && (schedule.battle_map_id == map.id ||
                    ScheduleBattleMap.exists?(schedule_id: schedule.id, battle_map_id: map.id))
      map.session_scope_schedule_id = schedule.id
    end

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
    Rails.logger.warn({ event: 'admin.sheet_items.broadcast_inventory_failed', error: e.class.name, message: e.message }.to_json)
  end
end
