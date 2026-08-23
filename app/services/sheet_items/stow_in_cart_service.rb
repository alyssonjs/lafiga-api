# frozen_string_literal: true

module SheetItems
  # Move item da bolsa para a CARROÇA do grupo (e de volta).
  #
  # Irmão do `StowOnMountService`, com uma diferença de fundo na AUTORIZAÇÃO:
  # a montaria é pessoal, a carroça é compartilhada. Qualquer um do grupo pode
  # tirar o item de qualquer um (decisão do mestre da mesa) — por isso quem
  # valida é a pertença ao grupo, não a posse do item.
  #
  # O item NUNCA muda de ficha: sai da carroça e volta para a bolsa do DONO,
  # mesmo que quem tirou tenha sido outro jogador.
  class StowInCartService
    class InvalidStow < StandardError; end

    def initialize(item:, group:, cart_id:, quantity:)
      @item = item
      @group = group
      @cart_id = cart_id.presence
      @quantity = quantity.to_i
    end

    def call
      sheet = item.sheet

      sheet.with_lock do
        item.lock!
        validate_quantity!
        cart = find_cart!
        destino = props_for(cart)

        return inventory_for(sheet) if same_container?(destino)

        move_quantity!(matching_stack(destino), destino)
        inventory_for(sheet)
      end
    end

    private

    attr_reader :item, :group, :cart_id, :quantity

    def validate_quantity!
      return if quantity.positive? && quantity <= item.quantity.to_i

      raise InvalidStow, "Quantidade inválida. Disponível: #{item.quantity.to_i}"
    end

    # `cart_id` em branco = TIRAR da carroça. Mesma convenção da aljava e da
    # montaria.
    def find_cart!
      return nil if cart_id.blank?

      cart = GroupCarts.find(group, cart_id)
      raise InvalidStow, 'Carroça não encontrada neste grupo' unless cart

      cart
    end

    def props_for(cart)
      props = (item.props_json || {}).deep_dup.stringify_keys
      props.delete(GroupCarts::CONTAINER_PROP)
      # Sair da carroça também tira da montaria: um item não pode estar nos dois.
      props.delete(SheetItem::MOUNT_CONTAINER_PROP) if cart
      props[GroupCarts::CONTAINER_PROP] = cart['id'] if cart
      props
    end

    def same_container?(destino)
      SheetItem.normalize_stack_props(item.props_json) == SheetItem.normalize_stack_props(destino)
    end

    def matching_stack(destino)
      candidato = item.dup
      candidato.quantity = quantity
      candidato.equipped = false
      candidato.slot = nil
      candidato.props_json = destino
      SheetItem.stackable_match_for(candidato)
    end

    def move_quantity!(destination, destino)
      if quantity == item.quantity.to_i && destination.nil?
        item.update!(equipped: false, slot: nil, props_json: destino)
        return
      end

      if destination
        destination.update!(quantity: destination.quantity.to_i + quantity)
      else
        movido = item.dup
        movido.quantity = quantity
        movido.equipped = false
        movido.slot = nil
        movido.props_json = destino
        movido.save!
      end

      restante = item.quantity.to_i - quantity
      restante.positive? ? item.update!(quantity: restante) : item.destroy!
    end

    def inventory_for(sheet)
      sheet.sheet_items.includes(:item).order(:position, :id).map(&:as_inventory_json)
    end
  end
end
