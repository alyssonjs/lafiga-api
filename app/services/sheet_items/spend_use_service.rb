# frozen_string_literal: true

module SheetItems
  # Gasta UM uso de um item que os declara (kit de primeiros socorros, kit de
  # herbalismo, varinha com cargas).
  #
  # PHB cap. 5: "O kit possui material suficiente para dez usos. Usando uma
  # ação, você pode gastar um uso do kit para estabilizar uma criatura que tenha
  # 0 pontos de vida, sem a necessidade de realizar um teste de Sabedoria
  # (Medicina)."
  #
  # Antes disto a mesa contava os usos NO NOME do item: `kit SOS x10`,
  # `kit SOS x9`, `Kit SOS x3` eram cinco entradas de catálogo para o mesmo kit.
  class SpendUseService
    class InvalidUse < StandardError; end

    def initialize(item:, amount: 1)
      @item = item
      @amount = amount.to_i
    end

    def call
      sheet = item.sheet

      sheet.with_lock do
        item.lock!
        max = item.uses_max
        raise InvalidUse, "#{item.item_name} não tem usos declarados." if max.nil?
        raise InvalidUse, 'Quantidade inválida.' unless amount.positive?

        restam = item.uses_remaining
        if amount > restam
          raise InvalidUse,
                "#{item.item_name} tem #{restam} uso#{'s' if restam != 1} restante#{'s' if restam != 1}."
        end

        props = (item.props_json || {}).deep_dup.stringify_keys
        props['uses_remaining'] = restam - amount
        item.update!(props_json: props)
        item
      end
    end

    # Devolve os usos ao máximo. Chamado pelo descanso.
    def self.restore!(item)
      return false if item.uses_max.nil?
      return false if item.uses_remaining == item.uses_max

      props = (item.props_json || {}).deep_dup.stringify_keys
      props.delete('uses_remaining') # ausente = cheio; não guarda o óbvio
      item.update!(props_json: props)
      true
    end

    private

    attr_reader :item, :amount
  end
end
