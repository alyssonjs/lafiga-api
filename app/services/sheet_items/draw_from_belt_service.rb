# frozen_string_literal: true

module SheetItems
  # SACAR do cinto: a arma presa vai para a MÃO, e o que estava na mão toma o
  # lugar dela no cinto.
  #
  # É o gesto que o PHB chama de interação livre do turno, e é UM movimento —
  # metade dele deixaria o personagem com duas armas na mesma mão ou com o
  # cinto e a mão ambos vazios. Por isso a troca acontece num lock só, e não
  # em duas chamadas que o cliente encadeia.
  #
  # O que sai da mão desce a mesma escada do `soltar!`: cinto (se a vocação
  # deixa e há vaga) → bolsa vestida (se cabe) → solto. Escudo e foco arcano
  # não entram em slot livre, e não é motivo para recusar o saque.
  class DrawFromBeltService
    class InvalidDraw < StandardError; end

    HANDS = %w[main_hand off_hand].freeze

    def initialize(item:, slot:)
      @item = item
      @slot = SheetItem.canonicalize_slot(slot).to_s
    end

    def call
      sheet = item.sheet
      sheet.with_lock do
        item.lock!
        validar!

        cinto_id = item.stored_on_belt_id
        deslocado = sheet.sheet_items.find { |si| si.equipped? && si.slot.to_s == slot && si.id != item.id }

        sacar!
        guardar_deslocado!(sheet, deslocado, cinto_id) if deslocado

        return inventario(sheet)
      end
    end

    private

    attr_reader :item, :slot

    def validar!
      raise InvalidDraw, 'Este item não está preso num cinto.' if item.stored_on_belt_id.blank?
      raise InvalidDraw, 'Só se saca para a mão principal ou secundária.' unless HANDS.include?(slot)
      raise InvalidDraw, 'Só arma se empunha.' unless StowOnBeltService.weapon?(item)
    end

    def sacar!
      props = (item.props_json || {}).deep_dup.stringify_keys
      props.delete(SheetItem::BELT_CONTAINER_PROP)
      item.update!(props_json: props, equipped: true, slot: slot)
    end

    # O que estava na mão embainha: primeiro o cinto que vagou, depois a bolsa
    # vestida, e por fim solto. Nunca some — só muda de sítio.
    def guardar_deslocado!(sheet, deslocado, cinto_id)
      props = (deslocado.props_json || {}).deep_dup.stringify_keys
      props.delete(SheetItem::BELT_CONTAINER_PROP)
      props.delete(SheetItem::BAG_CONTAINER_PROP)

      cinto = (sheet.sheet_items.find { |si| si.id == cinto_id } if cinto_id)
      if cinto && cabe_no_cinto?(sheet, cinto, deslocado)
        props[SheetItem::BELT_CONTAINER_PROP] = cinto.id
      else
        bolsa = sheet.sheet_items.find { |si| si.equipped? && si.slot.to_s == 'bag' }
        props[SheetItem::BAG_CONTAINER_PROP] = bolsa.id if bolsa&.bag_room_for?(deslocado)
      end

      deslocado.update!(props_json: props, equipped: false, slot: nil)
    end

    def cabe_no_cinto?(sheet, cinto, candidato)
      tipo = StowOnBeltService.slot_kind_for(candidato)
      return false if tipo.nil?

      total = cinto.belt_slot_props.to_h[tipo].to_i
      return false unless total.positive?

      # ⚠️ Excluir o SACADO pelo id, não pelo ponteiro: a associação já estava
      # carregada quando `sacar!` gravou, e a cópia em memória ainda mostra o
      # cinto. Ele já saiu — não pode ocupar a vaga que abriu.
      ocupados = sheet.sheet_items.count do |si|
        si.id != candidato.id && si.id != item.id &&
          si.stored_on_belt_id == cinto.id &&
          StowOnBeltService.slot_kind_for(si) == tipo
      end
      ocupados < total
    end

    def inventario(sheet)
      sheet.sheet_items.reload.includes(:item).order(:position, :id).map(&:as_inventory_json)
    end
  end
end
