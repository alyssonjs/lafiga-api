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
        validate_accepts_type!(quiver)
        validate_capacity!(quiver)
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
      # A mensagem dizia "flechas ou virotes" — deixou de ser verdade quando
      # pedra de funda e agulha de zarabatana passaram a contar como munição.
      raise InvalidAllocation, 'O item selecionado não é uma pilha de munição' unless ammunition.ammunition?
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

    # O recipiente aceita ESTA munição?
    #
    # Lista vazia = aceita qualquer uma. É o caso da aljava legada, que existe
    # em fichas desde antes de recipiente ter tipo declarado — recusar tudo ali
    # tiraria a munição do lugar em toda ficha antiga.
    def validate_accepts_type!(quiver)
      return if quiver.nil?

      aceitos = quiver.accepted_ammunition_indexes
      return if aceitos.empty?
      return if aceitos.include?(ammunition.item_index.to_s)

      # ⚠️ Compara a FAMÍLIA, não o índice inteiro: "flecha-de-fogo" é flecha,
      # e a aljava que aceita "flecha" tem de aceitá-la. Antes disto as três
      # munições mágicas do catálogo eram recusadas por toda aljava do banco.
      familia = ammunition.ammunition_family
      if familia.present?
        aceitas = aceitos.filter_map { |a| SheetItem.ammunition_family(a) }
        return if aceitas.include?(familia)
      end

      raise InvalidAllocation,
            "#{quiver.item_name} não guarda #{ammunition.item_name}."
    end

    # PHB: a aljava guarda ATÉ 20 flechas; o porta-virotes, até 20 virotes.
    # O limite é do recipiente — passar dele o esvaziaria de sentido.
    def validate_capacity!(quiver)
      return if quiver.nil?

      capacidade = quiver.ammunition_capacity
      return if capacidade.nil? || capacidade <= 0

      # O que já está lá MENOS o que sai desta mesma pilha (mover dentro do
      # mesmo recipiente não pode contar duas vezes).
      guardado = quiver.ammunition_stored_count
      guardado -= quantity if ammunition.ammunition_container_id == quiver.id.to_s
      livre = capacidade - guardado

      return if quantity <= livre

      raise InvalidAllocation,
            "#{quiver.item_name} guarda até #{capacidade}. Cabem mais #{[livre, 0].max}."
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
