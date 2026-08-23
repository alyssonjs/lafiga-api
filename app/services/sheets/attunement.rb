# frozen_string_literal: true

module Sheets
  # Regras de SINTONIA (attunement) — autoridade do servidor.
  #
  # A UI ja existia em `CharacterBag` (limite de 3, restricao por classe), mas
  # gravava por `persistItems`, que faz early-return no modo `controlled` — ou
  # seja, na ficha vinda da API a sintonia NUNCA persistiu (0 de 1041
  # sheet_items tinham a chave). Com o limite so no cliente, `countAttunedItems`
  # sempre dava 0 e o teto de 3 nunca mordia.
  #
  # Aqui o estado passa a viver em `sheet_items.props_json['attuned']` (chave ja
  # reservada em `SheetItem::PER_INSTANCE_PROP_KEYS`) e o teto e verificado no
  # servidor, dentro de transacao com lock da ficha.
  module Attunement
    # PHB: no maximo 3 itens sintonizados por criatura.
    LIMIT = 3

    PROP_KEY = 'attuned'

    module_function

    def attuned?(sheet_item)
      h = sheet_item.props_json
      h.is_a?(Hash) && ActiveModel::Type::Boolean.new.cast(h[PROP_KEY]) == true
    end

    # O catalogo do item exige sintonia?
    #
    # `MagicItem` e a autoridade; `Item` e um espelho que diverge em ~1% (medido:
    # 99/102 iguais). Consultamos o espelho so quando o item magico nao resolve —
    # e o mesmo par de fontes que o front usa em `findMagicItemAcross`.
    def required?(sheet_item)
      mi = magic_item_for(sheet_item)
      return !!mi.requires_attunement if mi

      !!sheet_item.item&.requires_attunement
    end

    # Texto livre do catalogo ("Somente feiticeiros"). Devolvido para a UI
    # mostrar; NAO bloqueia. Dos 60 itens que pedem sintonia, 1 tem nota, e ela
    # e uma frase — deduzir a classe dali seria adivinhacao, e barrar o jogador
    # por engano e pior do que nao barrar.
    def restriction_note(sheet_item)
      magic_item_for(sheet_item)&.attunement_note.presence
    end

    def attuned_count(sheet)
      sheet.sheet_items.count { |si| attuned?(si) }
    end

    # @return [Array(Boolean, String|nil)] [permitido, motivo]
    def can_attune?(sheet_item, sheet: nil)
      return [true, nil] if attuned?(sheet_item) # ja sintonizado: idempotente

      return [false, 'Este item não exige sintonia.'] unless required?(sheet_item)

      sheet ||= sheet_item.sheet
      if attuned_count(sheet) >= LIMIT
        return [false, "Limite de #{LIMIT} itens sintonizados atingido."]
      end

      [true, nil]
    end

    private_class_method def self.magic_item_for(sheet_item)
      idx = sheet_item.item_index.to_s.strip
      by_slug = MagicItem.find_by(slug: idx) if idx.present?
      return by_slug if by_slug

      name = sheet_item.item_name.to_s.strip
      return nil if name.blank?

      MagicItem.where('LOWER(name) = ?', name.downcase).first
    end
  end
end
