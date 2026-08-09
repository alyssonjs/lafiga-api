# frozen_string_literal: true

module SheetItems
  # Separa N unidades de uma pilha numa NOVA pilha independente (o inverso do
  # merge). A nova pilha é um clone exato (mesmo catálogo/props/notes/source),
  # não-equipada, colocada no fim da bolsa. Recusa itens equipados ou com estado
  # por-instância (cargas/sintonização), que não são pilhas fungíveis.
  class SplitStackService
    class InvalidSplit < StandardError; end

    def initialize(item:, quantity:)
      @item = item
      @quantity = quantity.to_i
    end

    def call
      sheet = @item.sheet

      sheet.with_lock do
        @item.lock!
        validate!

        new_item = @item.dup
        new_item.quantity = @quantity
        new_item.equipped = false
        new_item.slot = nil
        new_item.position = SheetItem.next_position_for(sheet.id)
        new_item.save!

        @item.update!(quantity: @item.quantity.to_i - @quantity)
      end

      inventory_for(sheet)
    end

    private

    def validate!
      raise InvalidSplit, 'Não é possível separar um item equipado' if @item.equipped?
      if SheetItem.per_instance_state?(@item.props_json)
        raise InvalidSplit, 'Itens com cargas ou sintonização não podem ser separados'
      end
      return if @quantity.positive? && @quantity < @item.quantity.to_i

      raise InvalidSplit, "Quantidade inválida. Separe de 1 a #{@item.quantity.to_i - 1}"
    end

    def inventory_for(sheet)
      sheet.sheet_items.reload.order(:position, :id).map(&:as_inventory_json)
    end
  end
end
