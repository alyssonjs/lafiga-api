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
    render json: { sheet_item: record.as_inventory_json }, status: (created ? :created : :ok)
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
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
    sync_equipped_chibi_token(@item, equipping: true)
    render json: { sheet_item: @item.as_inventory_json }, status: :ok
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/player/sheet_items/:id/unequip
  def unequip
    @item.update(equipped: false, slot: nil)
    sync_equipped_chibi_token(@item, equipping: false)
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
    render json: { sheet_items: items }, status: :ok
  rescue SheetItems::MergeStacksService::InvalidMerge => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/player/sheet_items/:id/split
  # body: { quantity } — separa N unidades desta pilha numa nova pilha.
  def split
    items = SheetItems::SplitStackService.new(item: @item, quantity: params[:quantity]).call
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

  # Espelha a arma de mão equipada no SNAPSHOT do token do personagem no mapa
  # da sessão (`token['chibiEquipment']`), server-authoritative + broadcast, para
  # que a camada de arma do chibi re-sincronize entre TODOS os clientes ao
  # equipar/desequipar. Antes, só o fluxo de arremesso/coleta atualizava esse
  # snapshot — um equip/unequip normal mudava a ficha mas NÃO o token, e o cliente
  # do não-dono (que não tem o inventário alheio) nunca via a troca. O front passa
  # o `battle_map_id` da sessão; achamos o token do personagem NESSE mapa. Best-
  # effort: qualquer falha só perde a sincronização visual, não bloqueia o equip.
  def sync_equipped_chibi_token(item, equipping:)
    map_id = params[:battle_map_id]
    return if map_id.blank?

    character = item.sheet&.character
    return unless character

    map = BattleMap.find_by(id: map_id)
    return unless map

    tokens = Array(map.tokens)
    token = tokens.find { |t| t['characterId'].to_s == character.id.to_s }
    return unless token

    token_id = token['id']
    if equipping
      # Só a arma de MÃO muda a camada de arma do chibi (armadura/escudo/acessórios
      # não). add_equipped_snapshot substitui a entrada main_hand pela nova arma.
      return unless item.slot.to_s == 'main_hand' && EquipmentRules.is_weapon?(item)

      next_tokens = BattleMapProjectiles.add_equipped_snapshot(tokens, token_id, item)
      changed = true
    else
      next_tokens, changed = BattleMapProjectiles.remove_equipped_snapshot(tokens, token_id, item)
    end
    return unless changed

    map.update!(tokens: next_tokens)
    MapRealtime::Broadcaster.tokens_changed(map, map.tokens, actor: @current_user)
  rescue StandardError => e
    Rails.logger.warn({ event: 'sheet_items.sync_chibi_token_failed', error: e.class.name, message: e.message }.to_json)
  end
end
