# frozen_string_literal: true

module SheetItems
  # Unifica MANUALMENTE duas pilhas do MESMO item (arrastar A sobre B). É mais
  # permissivo que `SheetItem.stackable_match_for` de propósito: o empilhamento
  # automático (no create) exige `props_json`/`notes`/`source` idênticos, então
  # itens que divergem nesses campos (ex.: munição que carregou
  # `quiver_sheet_item_id` residual) ficam como pilhas separadas — é justamente
  # essas que o jogador quer unir. Mantemos a exigência de MESMO catálogo,
  # não-equipado e sem estado por-instância (cargas/sintonização). O destino
  # preserva props/notes/source/position; a origem é absorvida e destruída.
  class MergeStacksService
    class InvalidMerge < StandardError; end

    def initialize(sheet:, source_id:, target_id:)
      @sheet = sheet
      @source_id = source_id.to_s
      @target_id = target_id.to_s
    end

    def call
      raise InvalidMerge, 'Origem e destino são o mesmo item' if @source_id == @target_id

      @sheet.with_lock do
        source = @sheet.sheet_items.lock.find_by(id: @source_id)
        target = @sheet.sheet_items.lock.find_by(id: @target_id)
        raise InvalidMerge, 'Item não encontrado nesta ficha' unless source && target

        validate_mergeable!(source, target)

        target.update!(quantity: target.quantity.to_i + source.quantity.to_i)
        source.destroy!
      end

      inventory_for(@sheet)
    end

    private

    def validate_mergeable!(source, target)
      raise InvalidMerge, 'Não é possível unir itens equipados' if source.equipped? || target.equipped?
      if per_instance?(source) || per_instance?(target)
        raise InvalidMerge, 'Itens com cargas ou sintonização não podem ser unidos'
      end
      raise InvalidMerge, 'Os itens precisam ser do mesmo tipo' unless same_item?(source, target)
    end

    def per_instance?(item)
      SheetItem.per_instance_state?(item.props_json)
    end

    # "Mesmo item" = mesmo catálogo (`item_index`) quando presente; senão, item
    # custom (sem item_id) com mesmo nome (case-insensitive) + categoria.
    def same_item?(a, b)
      if a.item_index.present? || b.item_index.present?
        a.item_index.present? && a.item_index.to_s == b.item_index.to_s
      else
        a.item_id.nil? && b.item_id.nil? &&
          a.item_name.to_s.strip.casecmp(b.item_name.to_s.strip).zero? &&
          a.category.to_s == b.category.to_s
      end
    end

    def inventory_for(sheet)
      sheet.sheet_items.reload.order(:position, :id).map(&:as_inventory_json)
    end
  end
end
