# frozen_string_literal: true

module SheetItems
  # Prende um item num CINTO da mesma ficha (ou solta: belt_id nulo).
  #
  # Mesmo desenho da bolsa: o item nunca muda de dono, a localização é o
  # ponteiro `belt_sheet_item_id`. O que muda é a natureza do recipiente —
  # o cinto conta SLOTS, não quilos, e cada slot tem vocação:
  #
  #   LIVRE       — arma, ferramenta ou aljava: coisa que se saca. A arma no
  #                 cinto está EQUIPADA no personagem mas fora das mãos; pelo
  #                 PHB, sacá-la é a interação livre com objeto do turno.
  #   CONSUMÍVEL  — poção e afins, prontos para beber.
  #
  # A vocação do slot deriva do ITEM (arma não entra em slot de consumível),
  # então o cliente não escolhe o slot — só o cinto.
  class StowOnBeltService
    class InvalidStow < StandardError; end

    def initialize(item:, belt_id:)
      @item = item
      @belt_id = belt_id.presence
    end

    def call
      sheet = item.sheet
      sheet.with_lock do
        item.lock!

        if belt_id.nil?
          soltar!
        else
          cinto = achar_cinto!(sheet)
          validar_nao_e_o_proprio!(cinto)
          tipo = tipo_de_slot!
          validar_vaga!(sheet, cinto, tipo)
          prender!(cinto)
        end

        return inventario(sheet)
      end
    end

    # Vocação do slot que ESTE item consome, ou InvalidStow se não cabe em
    # nenhuma. Público porque o front espelha a mesma pergunta.
    def tipo_de_slot!
      return 'free' if arma? || ferramenta? || aljava?
      return 'consumable' if consumivel?

      raise InvalidStow, 'Só arma, ferramenta, aljava ou consumível vão no cinto.'
    end

    private

    attr_reader :item, :belt_id

    def catalogo
      @catalogo ||= begin
        registro = (Item.find_by(api_index: item.item_index) if item.item_index.present?)
        registro || item.item
      end
    end

    def arma?
      return true if catalogo&.kind == 'weapon'

      # Arma mágica (kind `magic_item`) e linha manual: o gatilho canônico do
      # modo-arma é `weapon_sub_category` (instrument é a exceção histórica).
      # NÃO usar EquipmentRules.weapon_props aqui — o fallback dela SINTETIZA
      # props para qualquer item, e o cinto viraria bolsa.
      sub = (catalogo&.props || {})['weapon_sub_category'].presence ||
            (item.props_json || {})['weapon_sub_category'].presence
      sub.present? && sub.to_s != 'instrument'
    end

    def ferramenta?
      catalogo&.kind == 'tool'
    end

    def aljava?
      item.quiver?
    rescue StandardError
      false
    end

    def consumivel?
      catalogo&.kind == 'consumable'
    end

    def achar_cinto!(sheet)
      cinto = sheet.sheet_items.lock.find_by(id: belt_id)
      raise InvalidStow, 'O cinto não pertence a esta ficha.' unless cinto
      raise InvalidStow, 'O destino não é um cinto com slots.' unless cinto.belt?

      cinto
    end

    def validar_nao_e_o_proprio!(cinto)
      raise InvalidStow, 'Um cinto não se prende em si mesmo.' if cinto.id == item.id
    end

    # Vaga por VOCAÇÃO: o que já está preso no cinto consome slots do seu
    # próprio tipo, e o candidato precisa de um do dele.
    def validar_vaga!(sheet, cinto, tipo)
      total = cinto.belt_slot_props[tipo].to_i
      raise InvalidStow, 'Este cinto não tem slots desse tipo.' unless total.positive?

      presos = sheet.sheet_items
                    .where("props_json ->> '#{SheetItem::BELT_CONTAINER_PROP}' = ?", cinto.id.to_s)
                    .where.not(id: item.id)
      ocupados = presos.count do |si|
        self.class.new(item: si, belt_id: nil).tipo_de_slot! == tipo
      rescue InvalidStow
        false
      end
      return if ocupados < total

      raise InvalidStow, "Sem vaga: #{ocupados}/#{total} slots #{tipo == 'free' ? 'livres' : 'de consumível'} ocupados."
    end

    def soltar!
      props = (item.props_json || {}).deep_dup.stringify_keys
      props.delete(SheetItem::BELT_CONTAINER_PROP)
      item.update!(props_json: props)
    end

    def prender!(cinto)
      props = (item.props_json || {}).deep_dup.stringify_keys
      props[SheetItem::BELT_CONTAINER_PROP] = cinto.id
      # Preso no cinto não pode continuar noutro depósito: os ponteiros são
      # exclusivos entre si (o item está num lugar só).
      props.delete(SheetItem::BAG_CONTAINER_PROP)
      item.update!(props_json: props)
    end

    def inventario(sheet)
      sheet.sheet_items.includes(:item).order(:position, :id).map(&:as_inventory_json)
    end
  end
end
