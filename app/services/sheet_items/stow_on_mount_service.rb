# frozen_string_literal: true

module SheetItems
  # Move item da bolsa para a MONTARIA (e de volta).
  #
  # Espelha o `AllocateAmmunitionService`, que é o precedente desta base para
  # "item dentro de recipiente": o vínculo vive em `props_json`, o movimento
  # respeita empilhamento, e tudo acontece com lock da ficha.
  #
  # Diferença de fundo: a aljava é OUTRO SheetItem; a montaria é um companion
  # (jsonb em `sheets.companions`). Por isso o ponteiro guarda o `id` do
  # companion, não um `sheet_item_id` — e a validação confere que o companion
  # existe E é montaria.
  class StowOnMountService
    class InvalidStow < StandardError; end

    MOUNTS = %w[mount greater_mount].freeze

    def initialize(item:, companion_id:, quantity:)
      @item = item
      @companion_id = companion_id.presence
      @quantity = quantity.to_i
    end

    def call
      sheet = item.sheet

      sheet.with_lock do
        item.lock!
        validate_quantity!
        companion = find_mount!(sheet)
        destino = props_for(companion)

        return inventory_for(sheet) if same_container?(destino)

        move_quantity!(matching_stack(destino), destino)
        inventory_for(sheet)
      end
    end

    private

    attr_reader :item, :companion_id, :quantity

    def validate_quantity!
      return if quantity.positive? && quantity <= item.quantity.to_i

      raise InvalidStow, "Quantidade inválida. Disponível: #{item.quantity.to_i}"
    end

    # `companion_id` em branco = TIRAR da montaria (volta para a bolsa), mesma
    # convenção do `quiver_id` nulo na aljava.
    def find_mount!(sheet)
      return nil if companion_id.blank?

      companion = Array(sheet.companions).find { |c| c.is_a?(Hash) && c['id'].to_s == companion_id.to_s }
      raise InvalidStow, 'Montaria não encontrada nesta ficha' unless companion
      raise InvalidStow, 'Este companheiro não é uma montaria' unless MOUNTS.include?(companion['type'].to_s)

      companion
    end

    def props_for(companion)
      props = (item.props_json || {}).deep_dup.stringify_keys
      props.delete(SheetItem::MOUNT_CONTAINER_PROP)
      props[SheetItem::MOUNT_CONTAINER_PROP] = companion['id'] if companion
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
      # Pilha inteira e sem destino para fundir: só reetiqueta, sem criar linha.
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
