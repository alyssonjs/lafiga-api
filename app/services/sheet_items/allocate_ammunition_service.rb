# frozen_string_literal: true

module SheetItems
  class AllocateAmmunitionService
    class InvalidAllocation < StandardError; end

    def initialize(ammunition:, quiver_id:, quantity:)
      @ammunition = ammunition
      @quiver_id = quiver_id.presence
      @quantity = quantity.to_i
    end

    def call
      sheet = ammunition.sheet

      sheet.with_lock do
        ammunition.lock!
        validate_ammunition!
        validate_quantity!
        quiver = find_quiver!(sheet)
        destination_props = props_for(quiver)

        return inventory_for(sheet) if same_container?(destination_props)

        destination = matching_stack(destination_props)
        move_quantity!(destination, destination_props)
        inventory_for(sheet)
      end
    end

    private

    attr_reader :ammunition, :quiver_id, :quantity

    def validate_ammunition!
      raise InvalidAllocation, 'O item selecionado não é uma pilha de flechas ou virotes' unless ammunition.ammunition?
    end

    def validate_quantity!
      return if quantity.positive? && quantity <= ammunition.quantity.to_i

      raise InvalidAllocation, "Quantidade inválida. Disponível: #{ammunition.quantity.to_i}"
    end

    def find_quiver!(sheet)
      return nil if quiver_id.blank?

      quiver = sheet.sheet_items.lock.find_by(id: quiver_id)
      raise InvalidAllocation, 'A aljava não pertence a esta ficha' unless quiver
      raise InvalidAllocation, 'O recipiente selecionado não é uma aljava' unless quiver.quiver?

      quiver
    end

    def props_for(quiver)
      props = (ammunition.props_json || {}).deep_dup.stringify_keys
      props.delete(SheetItem::AMMUNITION_CONTAINER_PROP)
      props[SheetItem::AMMUNITION_CONTAINER_PROP] = quiver.id if quiver
      props
    end

    def same_container?(destination_props)
      current = SheetItem.normalize_stack_props(ammunition.props_json)
      wanted = SheetItem.normalize_stack_props(destination_props)
      current == wanted
    end

    def matching_stack(destination_props)
      candidate = ammunition.dup
      candidate.quantity = quantity
      candidate.equipped = false
      candidate.slot = nil
      candidate.props_json = destination_props
      SheetItem.stackable_match_for(candidate)
    end

    def move_quantity!(destination, destination_props)
      if quantity == ammunition.quantity.to_i && destination.nil?
        ammunition.update!(equipped: false, slot: nil, props_json: destination_props)
        return
      end

      if destination
        destination.update!(quantity: destination.quantity.to_i + quantity)
      else
        moved = ammunition.dup
        moved.quantity = quantity
        moved.equipped = false
        moved.slot = nil
        moved.props_json = destination_props
        moved.save!
      end

      remaining = ammunition.quantity.to_i - quantity
      remaining.positive? ? ammunition.update!(quantity: remaining) : ammunition.destroy!
    end

    def inventory_for(sheet)
      sheet.sheet_items.reload.order(:position, :id).map(&:as_inventory_json)
    end
  end
end
