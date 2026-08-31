# frozen_string_literal: true

module SheetItems
  # Prende um item num SLOT EXTERNO da bolsa (ou solta: bag_id nulo).
  #
  # É o bolso de fora da mochila: o item vai preso POR FORA, não guardado
  # dentro. Por isso tem ponteiro próprio (`bag_slot_sheet_item_id`) e conta
  # para a CONTAGEM de slots, não para a capacidade em kg — são dois sítios
  # diferentes na mesma bolsa.
  #
  # Mecânica igual à do cinto, com UMA diferença que é o pedido inteiro: o
  # slot externo NÃO tem vocação. O bolso de fora leva o que couber — arma,
  # corda, poção, tocha. Por isso a contagem é um número só, e não um par
  # livre/consumível.
  class StowOnBagSlotService
    class InvalidStow < StandardError; end

    def initialize(item:, bag_id:)
      @item = item
      @bag_id = bag_id.presence
    end

    def call
      sheet = item.sheet
      sheet.with_lock do
        item.lock!

        if bag_id.nil?
          soltar!
        else
          bolsa = achar_bolsa!(sheet)
          validar_nao_e_a_propria!(bolsa)
          validar_sem_ciclo!(sheet, bolsa)
          validar_vaga!(sheet, bolsa)
          prender!(bolsa)
        end

        return inventario(sheet)
      end
    end

    private

    attr_reader :item, :bag_id

    def achar_bolsa!(sheet)
      bolsa = sheet.sheet_items.lock.find_by(id: bag_id)
      raise InvalidStow, 'A bolsa não pertence a esta ficha.' unless bolsa
      raise InvalidStow, 'Esta bolsa não tem slots externos.' unless bolsa.bag_with_slots?

      bolsa
    end

    def validar_nao_e_a_propria!(bolsa)
      raise InvalidStow, 'Uma bolsa não se prende em si mesma.' if bolsa.id == item.id
    end

    # Mesma guarda de ciclo da capacidade: uma bolsa presa no bolso de outra é
    # permitido, mas A no bolso de B e B no bolso (ou dentro) de A é buraco
    # negro. Sobe as DUAS correntes — dentro e por fora — porque uma bolsa
    # pode estar guardada numa e pendurada noutra.
    def validar_sem_ciclo!(sheet, bolsa)
      visitados = Set.new([item.id])
      atual = bolsa
      passos = 0
      while atual
        raise InvalidStow, 'Isso criaria uma bolsa dentro dela mesma (ciclo).' if visitados.include?(atual.id)

        visitados << atual.id
        pai_id = atual.stored_on_bag_slot_id || atual.stored_in_bag_id
        break if pai_id.blank?

        passos += 1
        raise InvalidStow, 'Corrente de bolsas comprida demais.' if passos > 10

        atual = sheet.sheet_items.find_by(id: pai_id)
      end
    end

    def validar_vaga!(sheet, bolsa)
      total = bolsa.bag_slot_count
      presos = sheet.sheet_items
                    .where("props_json ->> '#{SheetItem::BAG_SLOT_CONTAINER_PROP}' = ?", bolsa.id.to_s)
                    .where.not(id: item.id)
                    .count
      return if presos < total

      raise InvalidStow, "Sem vaga: #{presos}/#{total} slots externos ocupados."
    end

    def soltar!
      props = (item.props_json || {}).deep_dup.stringify_keys
      props.delete(SheetItem::BAG_SLOT_CONTAINER_PROP)
      item.update!(props_json: props)
    end

    def prender!(bolsa)
      props = (item.props_json || {}).deep_dup.stringify_keys
      props[SheetItem::BAG_SLOT_CONTAINER_PROP] = bolsa.id
      # Ponteiros EXCLUSIVOS: o item está num sítio só. Preso por fora não
      # está dentro de bolsa nenhuma nem no cinto.
      props.delete(SheetItem::BAG_CONTAINER_PROP)
      props.delete(SheetItem::BELT_CONTAINER_PROP)
      item.update!(props_json: props, equipped: false, slot: nil)
    end

    def inventario(sheet)
      sheet.sheet_items.reload.includes(:item).order(:position, :id).map(&:as_inventory_json)
    end
  end
end
