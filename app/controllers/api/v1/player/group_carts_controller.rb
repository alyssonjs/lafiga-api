# Depósitos móveis do grupo (carroça, carruagem, vagão…).
#
# Autorização por PERTENCER AO GRUPO, não por posse do item: a carroça é
# compartilhada e qualquer um do grupo mexe nela (decisão do mestre da mesa).
# O item continua na ficha do dono — só o ponteiro muda.
class Api::V1::Player::GroupCartsController < ApplicationController
  before_action :authorize_request
  before_action :set_group

  # GET /api/v1/player/groups/:group_id/carts
  def index
    render json: { carts: GroupCarts.all(@group).map { |c| serialize(c) } }, status: :ok
  end

  # POST /api/v1/player/groups/:group_id/carts
  # body: { cart: { id, name, item_index?, weight_lb?, mounts?: [{sheet_id, companion_id}] } }
  def create
    payload = cart_payload
    return render json: { error: 'Carroça inválida: `id` e `name` obrigatórios.' }, status: :unprocessable_entity if payload.nil?

    Group.transaction do
      group = Group.lock.find(@group.id)
      lista = GroupCarts.all(group).reject { |c| c['id'].to_s == payload['id'].to_s }
      group.update!(carts: lista + [payload])
      @group = group
    end

    render json: { carts: GroupCarts.all(@group.reload).map { |c| serialize(c) } }, status: :created
  end

  # PATCH /api/v1/player/groups/:group_id/carts/:id
  # Usado também para atrelar/desatrelar montarias (`mounts`).
  def update
    achou = false

    Group.transaction do
      group = Group.lock.find(@group.id)
      lista = GroupCarts.all(group).map do |c|
        next c unless c['id'].to_s == params[:id].to_s

        achou = true
        c.merge(patch_attributes).merge('id' => c['id'])
      end
      group.update!(carts: lista) if achou
      @group = group
    end

    return render json: { error: 'Carroça não encontrada.' }, status: :not_found unless achou

    render json: { carts: GroupCarts.all(@group.reload).map { |c| serialize(c) } }, status: :ok
  end

  # DELETE /api/v1/player/groups/:group_id/carts/:id
  def destroy
    Group.transaction do
      group = Group.lock.find(@group.id)
      # Solta a carga ANTES de apagar: cada item volta para a bolsa do dono.
      GroupCarts.release!(group, params[:id])
      group.update!(carts: GroupCarts.all(group).reject { |c| c['id'].to_s == params[:id].to_s })
      @group = group
    end

    render json: { carts: GroupCarts.all(@group.reload).map { |c| serialize(c) } }, status: :ok
  end

  # GET /api/v1/player/groups/:group_id/carts/:id/items
  #
  # Itens de TODAS as fichas do grupo que estão nesta carroça. É o único ponto
  # onde um jogador lê `sheet_items` de outra ficha — por isso a autorização é
  # a de grupo, e o payload leva o dono de cada item.
  def items
    cart = GroupCarts.find(@group, params[:id])
    return render json: { error: 'Carroça não encontrada.' }, status: :not_found unless cart

    linhas = GroupCarts.items(@group, params[:id]).map do |si|
      # `as_inventory_json` guarda o peso em `props['weight_lb']`; subimos uma
      # cópia no topo para o front não ter de escavar props em cada linha.
      si.as_inventory_json.merge(
        weight_lb: GroupCarts.item_weight_lb(si),
        owner_character_id: si.sheet&.character&.id,
        owner_name: si.sheet&.character&.name,
      )
    end

    render json: {
      cart: serialize(cart),
      items: linhas,
      carried_lb: linhas.sum { |l| l[:weight_lb].to_f * l[:quantity].to_i },
    }, status: :ok
  end

  # POST /api/v1/player/groups/:group_id/carts/:id/stow
  # body: { sheet_item_id, quantity }
  #
  # Vive AQUI, e não no `sheet_items_controller`, de propósito: quem autoriza é
  # a pertença ao GRUPO. No controller de itens a guarda é posse da ficha, e
  # qualquer um do grupo pode mexer na carroça.
  def stow
    item = sheet_item_in_group!(params[:sheet_item_id])
    return render json: { error: 'Item não pertence a este grupo.' }, status: :not_found unless item

    SheetItems::StowInCartService.new(
      item: item,
      group: @group,
      cart_id: params[:remove] ? nil : params[:id],
      quantity: params[:quantity] || item.quantity,
    ).call

    render json: { cart_id: params[:id] }, status: :ok
  rescue SheetItems::StowInCartService::InvalidStow => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # O item tem que ser de ALGUMA ficha do grupo — não precisa ser do usuário.
  def sheet_item_in_group!(id)
    return nil if id.blank?

    sheet_ids = @group.characters.filter_map { |c| c.sheet&.id }
    SheetItem.where(sheet_id: sheet_ids).find_by(id: id)
  end

  def serialize(cart)
    cart.merge(
      'capacity_lb' => GroupCarts.capacity_lb(@group, cart),
      # Nome de quem puxa, para a ficha não ter de carregar as fichas alheias.
      'mounts' => GroupCarts.mounts_of(cart).map do |m|
        m.merge('name' => GroupCarts.mount_name(@group, m))
      end,
    )
  end

  def cart_payload
    raw = params[:cart]
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    return nil unless raw.is_a?(Hash)

    h = raw.deep_stringify_keys
    return nil if h['id'].to_s.strip.empty? || h['name'].to_s.strip.empty?

    h
  end

  def patch_attributes
    raw = params[:cart]
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
  end

  # Membro do grupo (tem personagem nele) OU o Mestre.
  def set_group
    @group = Group.find(params[:group_id])
    return if Group.user_is_dm?(@current_user)
    return if @group.characters.exists?(user_id: @current_user.id)

    render json: { error: 'Not found' }, status: :not_found
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end
end
