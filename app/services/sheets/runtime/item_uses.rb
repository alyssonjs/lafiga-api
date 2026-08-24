# frozen_string_literal: true

module Sheets
  module Runtime
    # Recuperacao de USOS de item no descanso.
    #
    # Cobre duas familias que compartilham o mesmo contador por instancia
    # (`sheet_items.props_json['uses_remaining']`):
    #   - kits e ferramentas mundanas com usos limitados (ex: Kit de Primeiros
    #     Socorros, "material suficiente para dez usos");
    #   - cargas de item magico.
    #
    # A recarga vem do item BASE (`props['uses_recharge']`, tokens `short`/`long`
    # de MagicItemCatalog). Item sem token nao recupera em descanso — e o caso
    # do kit consumivel, que so volta comprando material novo.
    class ItemUses
      # @param sheet [Sheet]
      # @param kind [Symbol] :short ou :long
      # @return [Integer] quantos itens foram restaurados
      def self.restore_all!(sheet, kind:)
        return 0 unless sheet

        restaurados = 0
        sheet.sheet_items.includes(:item).find_each do |item|
          next unless item.uses_max
          next unless MagicItemCatalog.recharges_on?(item.uses_recharge, kind)
          next if item.uses_remaining == item.uses_max # ja cheio: nao escreve a toa

          SheetItems::SpendUseService.restore!(item)
          restaurados += 1
        end
        restaurados
      end
    end
  end
end
