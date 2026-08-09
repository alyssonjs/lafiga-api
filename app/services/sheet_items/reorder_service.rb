# frozen_string_literal: true

module SheetItems
  # Reordena a bolsa de uma ficha a partir de uma lista ORDENADA de ids
  # (arrastar-e-soltar). Recebe os ids dos itens da bolsa na ordem desejada e
  # grava `position` 1..N. Itens não citados (equipados, ou de outra aba) vão
  # para o fim preservando a ordem atual. Usa `update_columns` de propósito:
  # mexer só em `position` NÃO deve disparar o callback de exclusividade de slot.
  class ReorderService
    class InvalidReorder < StandardError; end

    def initialize(sheet:, ordered_ids:)
      @sheet = sheet
      @ordered_ids = Array(ordered_ids).map(&:to_s).reject(&:blank?)
    end

    def call
      raise InvalidReorder, 'Lista de ordenação vazia' if @ordered_ids.empty?

      @sheet.with_lock do
        by_id = @sheet.sheet_items.where(id: @ordered_ids).index_by { |i| i.id.to_s }
        position = 0

        @ordered_ids.each do |id|
          item = by_id[id]
          next unless item

          position += 1
          item.update_columns(position: position) if item.position != position
        end

        # Qualquer item não listado (equipado/outra aba) preserva ordem relativa
        # e é empurrado para o fim, mantendo `position` denso e sem colisões.
        @sheet.sheet_items.where.not(id: by_id.keys).order(:position, :id).each do |item|
          position += 1
          item.update_columns(position: position) if item.position != position
        end
      end

      inventory_for(@sheet)
    end

    private

    def inventory_for(sheet)
      sheet.sheet_items.reload.order(:position, :id).map(&:as_inventory_json)
    end
  end
end
