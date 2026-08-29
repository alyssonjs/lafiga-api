# frozen_string_literal: true

module Sheets
  # Regras da ARMA DE PACTO (Pacto da Lâmina, Bruxo) — autoridade do servidor.
  #
  # ⚠️ POR QUE O SERVIDOR, e não um campo no `classData` do front. `class_data`
  # não existe no banco: é DERIVADO do resumo da ficha a cada carregamento, então
  # gravar o vínculo ali sumiria no próximo reload. O estado por-instância de item
  # já tem endereço — `sheet_items.props_json` — e é o mesmo lugar da sintonia.
  #
  # ⚠️ POR QUE UM ENDPOINT, e não um PATCH comum. A regra tem um INVARIANTE que
  # só o servidor pode garantir: **exatamente uma** arma de pacto por ficha ("a
  # arma deixa de ser a arma de pacto se você realizar o ritual em outra"). Com
  # a exclusividade no cliente, dois dispositivos vinculariam duas armas e as
  # DUAS contariam como mágicas. É o mesmo motivo do teto de 3 da sintonia.
  #
  # O QUE O SERVIDOR NÃO CHECA: se o personagem tem o Pacto da Lâmina. Isso
  # depende das invocações/dádiva, que o front já resolve
  # (`hasPactOfTheBlade`), e barrar por engano é pior do que não barrar — a
  # mesma escolha feita na nota de restrição da sintonia.
  module PactWeapon
    PROP_KEY = 'pact_weapon'

    module_function

    def pact_weapon?(sheet_item)
      h = sheet_item.props_json
      h.is_a?(Hash) && ActiveModel::Type::Boolean.new.cast(h[PROP_KEY]) == true
    end

    # A arma de pacto é CORPO A CORPO (PHB: "essa arma corpo a corpo").
    def melee_weapon?(sheet_item)
      props = EquipmentRules.weapon_props(sheet_item)
      return false if props.blank?

      tipo = (props[:type] || props['type']).to_s
      tipo.empty? || tipo == 'melee'
    rescue StandardError
      false
    end

    # @return [Array(Boolean, String|nil)] [permitido, motivo]
    def can_bind?(sheet_item)
      return [true, nil] if pact_weapon?(sheet_item) # idempotente

      return [false, 'A arma de pacto é corpo a corpo.'] unless melee_weapon?(sheet_item)

      [true, nil]
    end

    # Vincula ESTA arma e desvincula todas as outras da mesma ficha, no mesmo
    # movimento — é a exclusividade que dá sentido ao endpoint.
    #
    # @return [Array<SheetItem>] itens alterados (para o broadcast)
    def bind!(sheet_item, sheet: nil)
      sheet ||= sheet_item.sheet
      alterados = []

      sheet.sheet_items.each do |si|
        next unless pact_weapon?(si)
        next if si.id == sheet_item.id

        si.update!(props_json: (si.props_json || {}).merge(PROP_KEY => false))
        alterados << si
      end

      unless pact_weapon?(sheet_item)
        sheet_item.update!(props_json: (sheet_item.props_json || {}).merge(PROP_KEY => true))
      end
      alterados << sheet_item
      alterados
    end

    def unbind!(sheet_item)
      sheet_item.update!(props_json: (sheet_item.props_json || {}).merge(PROP_KEY => false))
      sheet_item
    end
  end
end
