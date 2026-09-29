# frozen_string_literal: true

module Crafting
  # CONCLUIR uma criação: é aqui, e só aqui, que os materiais saem da bolsa.
  #
  # Numa transação: desconta de onde estão (solto primeiro, carroça por último;
  # nunca item equipado), guarda em `consumed` o que saiu de onde, e entrega o
  # produto pelo `SheetItem.stack_or_create!` — a mesma porta de toda adição, então
  # a poção criada soma com as que o personagem já tinha.
  #
  # ⚠️ Trava a FICHA antes das linhas da bolsa: é a ordem do `stack_or_create!`.
  # Na ordem inversa, uma compra ao mesmo tempo que a conclusão se prendiam uma
  # na outra.
  #
  # Material que falta derruba a conclusão (`MissingMaterials`) — a menos que o
  # Mestre force: aí desconta o que houver e conclui mesmo assim.
  class Complete
    class MissingMaterials < StandardError
      attr_reader :missing

      def initialize(missing)
        @missing = missing
        super("Faltam materiais: #{missing.map { |m| "#{fmt(m[:missing])} #{m[:unit]} de #{m[:name]}" }.join(', ')}")
      end

      private

      def fmt(n)
        n.to_d.frac.zero? ? n.to_i.to_s : n.to_s
      end
    end

    class Invalid < StandardError; end

    def self.call(craft:, force: false)
      new(craft, force).call
    end

    def initialize(craft, force)
      @craft = craft
      @force = force
    end

    def call
      SheetCraft.transaction do
        @craft.sheet.lock!
        @craft.lock!
        raise Invalid, 'Esta criação já foi concluída' unless @craft.in_progress?

        recipe = @craft.crafting_recipe
        raise Invalid, 'A receita desta criação foi apagada' unless recipe&.result_item

        inv = Inventory.new(@craft.sheet, lock: true)
        plano = Requirements.of(recipe, @craft.quantity, available: ->(id) { inv.total(id) })
        faltas = plano.filter_map do |r|
          falta = r[:need] - inv.total(r[:item_id])
          { name: r[:ingredient].display_name, unit: r[:ingredient].unit, missing: falta } if falta.positive?
        end
        raise MissingMaterials, faltas if faltas.any? && !@force

        consumido = plano.flat_map { |r| descontar(inv, r) }
        produto = entregar(recipe.result_item)
        @craft.update!(status: 'done', completed_at: Time.current, consumed: consumido,
                       product_sheet_item_id: produto.id,
                       days_worked: [@craft.days_worked, @craft.days_required].max)
        @craft
      end
    end

    private

    def descontar(inv, requisito)
      resto = requisito[:need]
      saiu = []
      (inv.by_item[requisito[:item_id]] || []).each do |linha|
        break if resto <= 0

        tira = [linha.quantity, resto].min
        next if tira <= 0

        resto -= tira
        si = SheetItem.find(linha.sheet_item_id)
        tira >= si.quantity ? si.destroy! : si.update!(quantity: si.quantity - tira)
        saiu << { 'item_id' => linha.item_id, 'name' => requisito[:ingredient].display_name,
                  'quantity' => tira, 'unit' => requisito[:ingredient].unit, 'lugar' => linha.lugar }
      end
      saiu
    end

    def entregar(item)
      props = item.props.is_a?(Hash) ? item.props.dup : {}
      if item.kind == 'magic_item'
        props['magical'] = true
        props['rarity'] ||= item.rarity if item.rarity.present?
      end
      novo = SheetItem.new(
        sheet_id: @craft.sheet_id, item_id: item.id, item_index: item.api_index,
        item_name: item.name, category: Drawer.for(item), quantity: @craft.quantity,
        equipped: false, source: 'crafted', props_json: props,
      )
      SheetItem.stack_or_create!(novo).first
    end
  end
end
