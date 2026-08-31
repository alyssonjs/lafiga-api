class Api::V1::Player::SheetItemsController < ApplicationController
  before_action :authorize_request
  before_action :ensure_ownership_by_sheet, only: [:index, :create, :reorder]
  before_action :ensure_ownership_by_item, only: [:update, :destroy]
  before_action :ensure_ownership_by_item_for_member, only: [:equip, :unequip, :attune, :unattune, :bind_pact_weapon, :unbind_pact_weapon, :allocate_ammunition, :stow_on_mount, :stow_in_bag, :stow_on_belt, :draw_from_belt, :stow_on_bag_slot, :merge, :split, :spend_use]

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
    slot = SheetItem.canonicalize_slot(params[:slot])
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

  # POST /api/v1/player/sheet_items/:id/attune
  #
  # Grava `props_json['attuned']`. O teto de 3 e verificado AQUI, com a ficha
  # travada — o cliente ja tinha a regra, mas o `persistItems` do CharacterBag
  # faz early-return no modo controlado e a sintonia nunca chegava ao banco.
  def attune
    SheetItem.transaction do
      sheet = Sheet.lock.find(@item.sheet_id)
      ok, reason = Sheets::Attunement.can_attune?(@item, sheet: sheet)
      raise ActiveRecord::Rollback, reason unless ok

      merged = (@item.props_json || {}).merge(Sheets::Attunement::PROP_KEY => true)
      @item.update!(props_json: merged)
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

  # POST /api/v1/player/sheet_items/:id/spend_use  { amount? }
  #
  # Gasta um uso do kit (ou uma carga do item magico). O limite e do SERVIDOR:
  # duas abas abertas gastariam o mesmo ultimo uso se so o cliente contasse.
  def spend_use
    SheetItems::SpendUseService.new(item: @item, amount: params[:amount] || 1).call
    broadcast_inventory_changed(@item)
    render json: { sheet_item: @item.reload.as_inventory_json }, status: :ok
  rescue SheetItems::SpendUseService::InvalidUse => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/player/sheet_items/:id/bind_pact_weapon
  #
  # Marca ESTA arma como a arma de pacto do Bruxo e DESMARCA as demais da mesma
  # ficha, na mesma transacao. A exclusividade e o motivo do endpoint existir:
  # com ela so no cliente, dois dispositivos vinculariam duas armas e as DUAS
  # contariam como magicas (fura resistencia a dano nao-magico).
  def bind_pact_weapon
    alterados = []
    SheetItem.transaction do
      sheet = Sheet.lock.find(@item.sheet_id)
      ok, reason = Sheets::PactWeapon.can_bind?(@item)
      raise ActiveRecord::Rollback, reason unless ok

      alterados = Sheets::PactWeapon.bind!(@item, sheet: sheet)
      @bind_ok = true
    end

    unless @bind_ok
      _, reason = Sheets::PactWeapon.can_bind?(@item)
      return render json: { error: reason || 'Nao foi possivel vincular a arma de pacto.' },
                    status: :unprocessable_entity
    end

    broadcast_inventory_changed(@item)
    render json: { sheet_items: alterados.map { |si| si.reload.as_inventory_json } }, status: :ok
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/player/sheet_items/:id/unbind_pact_weapon
  #
  # Sempre permitido: dispensar a arma de pacto nao exige acao no PHB.
  def unbind_pact_weapon
    Sheets::PactWeapon.unbind!(@item)
    broadcast_inventory_changed(@item)
    render json: { sheet_item: @item.reload.as_inventory_json }, status: :ok
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/player/sheet_items/:id/unattune
  #
  # Sempre permitido: quebrar a sintonia e uma acao livre no PHB, e prender o
  # jogador num item cheio abriria um beco sem saida quando o teto encher.
  def unattune
    merged = (@item.props_json || {}).merge(Sheets::Attunement::PROP_KEY => false)
    @item.update!(props_json: merged)
    broadcast_inventory_changed(@item)
    render json: { sheet_item: @item.as_inventory_json }, status: :ok
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/player/sheet_items/:id/stow_on_mount
  # body: { companion_id: <id do companion> | null, quantity: integer }
  #
  # `companion_id` nulo TIRA da montaria (volta para a bolsa) — mesma convenção
  # do `quiver_id` nulo na alocação de munição.
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

  # POST /api/v1/player/sheet_items/:id/stow_in_bag
  # body: { bag_id: SheetItem id | null }
  #
  # Guarda o item numa BOLSA da mesma ficha (nulo tira). Capacidade em kg e
  # guarda de ciclo são do SERVIÇO — duas abas abertas guardariam o mesmo
  # último quilo se só o cliente somasse.
  def stow_in_bag
    items = SheetItems::StowInBagService.new(
      item: @item,
      bag_id: params[:bag_id],
      quantity: params[:quantity]
    ).call
    broadcast_inventory_changed(@item)
    render json: { sheet_items: items }, status: :ok
  rescue SheetItems::StowInBagService::InvalidStow => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # POST /api/v1/player/sheet_items/:id/stow_on_belt
  # body: { belt_id: SheetItem id | null }
  #
  # Prende no CINTO (nulo solta). Vocação do slot e contagem são do SERVIÇO;
  # arma presa fica equipada-fora-das-mãos (sacar = interação livre, PHB).
  def stow_on_belt
    items = SheetItems::StowOnBeltService.new(item: @item, belt_id: params[:belt_id]).call
    broadcast_inventory_changed(@item)
    render json: { sheet_items: items }, status: :ok
  rescue SheetItems::StowOnBeltService::InvalidStow => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/player/sheet_items/:id/stow_on_bag_slot
  # body: { bag_id: SheetItem id | null }
  #
  # Prende no SLOT EXTERNO da bolsa (nulo solta). É o bolso de fora: sem
  # vocação (leva o que couber) e sem peso — conta vaga, não quilo.
  def stow_on_bag_slot
    items = SheetItems::StowOnBagSlotService.new(item: @item, bag_id: params[:bag_id]).call
    broadcast_inventory_changed(@item)
    render json: { sheet_items: items }, status: :ok
  rescue SheetItems::StowOnBagSlotService::InvalidStow => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/player/sheet_items/:id/draw_from_belt
  # body: { slot: 'main_hand' | 'off_hand' }
  #
  # SACAR: a arma do cinto vai para a mão e o que estava lá toma o lugar dela
  # no cinto. UM movimento — meio dele deixaria duas armas na mesma mão.
  def draw_from_belt
    items = SheetItems::DrawFromBeltService.new(item: @item, slot: params[:slot]).call
    broadcast_inventory_changed(@item)
    render json: { sheet_items: items }, status: :ok
  rescue SheetItems::DrawFromBeltService::InvalidDraw => e
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
