# frozen_string_literal: true

module Crafting
  # O que o personagem TEM de cada item do catálogo, e ONDE está.
  #
  # ⚠️ Conta tudo que é dele, inclusive o que está guardado na carroça do grupo
  # (decisão da mesa, 29/09) — e diz o lugar, para o Mestre saber de onde vai
  # sair. Item EQUIPADO não entra: a espada na mão não é matéria-prima.
  #
  # A quantidade da bolsa já está na unidade do item do catálogo (a essência é
  # vendida por ml, então 30 na bolsa são 30 ml) — é a mesma unidade em que a
  # receita foi escrita contra aquele item.
  class Inventory
    Linha = Struct.new(:sheet_item_id, :item_id, :quantity, :lugar, :prioridade, keyword_init: true)

    # Ordem de CONSUMO: o que está solto sai primeiro, a carroça por último.
    PRIORIDADE = { solto: 0, bolsa: 1, cinto: 2, aljava: 2, montaria: 3, carroca: 4 }.freeze

    def initialize(sheet, lock: false)
      @sheet = sheet
      @lock = lock
    end

    # { item_id => [Linha, ...] }, cada lista na ordem de consumo.
    def by_item
      @by_item ||= begin
        rel = @sheet.sheet_items.where.not(item_id: nil).where(equipped: false)
        rel = rel.lock if @lock
        itens = rel.to_a
        nomes = nomes_dos_recipientes(itens)
        itens.group_by(&:item_id).transform_values do |ls|
          ls.map { |si| linha(si, nomes) }.sort_by { |l| [l.prioridade, l.sheet_item_id] }
        end
      end
    end

    def total(item_id)
      (by_item[item_id] || []).sum(&:quantity)
    end

    # [{ lugar:, quantity: }] somado por lugar — o que a tela mostra.
    def onde(item_id)
      (by_item[item_id] || []).group_by(&:lugar).map { |lugar, ls| { lugar: lugar, quantity: ls.sum(&:quantity) } }
    end

    private

    def linha(si, nomes)
      props = si.props_json.is_a?(Hash) ? si.props_json : {}
      tipo, lugar =
        if props['cart_id'].present? then [:carroca, 'Carroça do grupo']
        elsif props['mount_companion_id'].present? then [:montaria, 'Montaria']
        elsif (id = props['bag_sheet_item_id'] || props['bag_slot_sheet_item_id']).present? then [:bolsa, nomes[id.to_i] || 'Bolsa']
        elsif (id = props['belt_sheet_item_id']).present? then [:cinto, nomes[id.to_i] || 'Cinto']
        elsif (id = props['quiver_sheet_item_id']).present? then [:aljava, nomes[id.to_i] || 'Aljava']
        else [:solto, 'Inventário']
        end
      Linha.new(sheet_item_id: si.id, item_id: si.item_id, quantity: si.quantity.to_i, lugar: lugar, prioridade: PRIORIDADE[tipo])
    end

    def nomes_dos_recipientes(itens)
      ids = itens.flat_map do |si|
        p = si.props_json.is_a?(Hash) ? si.props_json : {}
        p.values_at('bag_sheet_item_id', 'bag_slot_sheet_item_id', 'belt_sheet_item_id', 'quiver_sheet_item_id')
      end.compact.map(&:to_i).uniq
      return {} if ids.empty?

      SheetItem.where(id: ids).pluck(:id, :item_name).to_h
    end
  end
end
