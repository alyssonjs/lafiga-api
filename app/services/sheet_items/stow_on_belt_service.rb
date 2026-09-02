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
          tipo = tipo_de_slot!(cinto)
          validar_vaga!(sheet, cinto, tipo)
          prender!(cinto, tipo)
        end

        return inventario(sheet)
      end
    end

    # Peças de vestuário. Espelho de `WARDROBE_MAGIC_SUBCATEGORIES` (front,
    # `compendiumMagicTabCategories.ts`) mais o anel, que só tem base mundana.
    #
    # Lista EXPLÍCITA, e não "gear que não é outra coisa": `gear` é o balde
    # genérico do catálogo — 300 linhas, a maioria sem categoria — e varrê-lo
    # inteiro para o cinto transformava a vaga num segundo inventário.
    #
    # ⚠️ CINTO fora da lista de propósito: cinto veste-se na cintura, não se
    # pendura noutro cinto. Deixá-lo entrar abria a pergunta do cinto-dentro-do-
    # cinto, que nenhum guard de ciclo responde hoje.
    WARDROBE_PIECES = %w[
      ring earrings necklace choker amulet circlet bracelet_left bracelet_right
      gloves gauntlets boots anklet cloak helmet mask goggles brooch locket
    ].freeze


    # Vocação SEM levantar erro — `nil` quando o item não vai em cinto nenhum.
    # Serviço de sacar e contagem de vagas usam isto.
    def self.slot_kind_for(item)
      new(item: item, belt_id: nil).tipo_de_slot!
    rescue InvalidStow
      nil
    end

    # `true` para o que se empunha. O gatilho é o canônico — ver `arma?`.
    def self.weapon?(item)
      new(item: item, belt_id: nil).send(:arma?)
    end

    # Vocação do slot que ESTE item consome, ou InvalidStow se não cabe em
    # nenhuma. Público porque o front espelha a mesma pergunta.
    #
    # `cinto` opcional: o CINTO DE PERNA aceita menos coisa que o da cintura —
    # a mesma arma pode caber num e não no outro, então a pergunta depende de
    # ONDE se está pendurando.
    def tipo_de_slot!(cinto = nil)
      return tipo_de_slot_perna! if cinto && self.class.leg_belt?(cinto)

      # Consumível PRIMEIRO: a poção tem vaga própria, e um dia um consumível
      # vai ter nome de vestuário. A vaga certa importa mais que a ordem.
      return 'consumable' if consumivel?
      return 'free' if arma? || ferramenta? || aljava? || livro? || instrumento? || vestuario?

      raise InvalidStow, 'Este item não vai em cinto.'
    end

    # CINTO DE PERNA: só o que se enfia num coldre de coxa — arma PEQUENA
    # (adaga, agulha: a propriedade `light` do PHB) e consumível.
    #
    # ⚠️ Cabe menos DE PROPÓSITO. Espada longa, aljava, livro e instrumento vão
    # no cinturão da cintura; deixá-los aqui faria do coldre um segundo cinto
    # com outro nome, e a mesa perde a razão de ter os dois.
    def tipo_de_slot_perna!
      return 'consumable' if consumivel?
      return 'free' if arma_pequena?

      raise InvalidStow, 'No cinto de perna só cabem armas pequenas e consumíveis.'
    end

    # O cinto está vestido numa PERNA?
    def self.leg_belt?(cinto)
      SheetItem::LEG_BELT_SLOTS.include?(cinto.slot.to_s)
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

    # Arma PEQUENA = arma com a propriedade `light` do PHB (adaga, clava leve,
    # machadinha). É o teste do livro, não um palpite por nome — e a agulha
    # caseira do mestre passa a caber assim que ele marcar `leve` no editor.
    def arma_pequena?
      return false unless arma?

      props = begin
        EquipmentRules.weapon_props(item) || {}
      rescue StandardError
        {}
      end
      props[:light] == true || props['light'] == true
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

    # Livro/tomo pendura no cinto do estudioso. `kind` é a chave canônica; o
    # nome cobre a linha que o mestre criou à mão, sem entrada no catálogo.
    def livro?
      return true if catalogo&.kind == 'book'

      # ANCORADO no início, como o leitor do front: "Broche do Livro do Vazio"
      # não é livro. Falso negativo é barato — o mestre declara o `kind`.
      nome_normalizado.match?(/\A(?:livros?|tomos?|grimorios?|codex)\b/)
    end

    # Instrumento: 13 dos 14 do catálogo são `kind: tool` e já passavam por
    # `ferramenta?`; UM é `gear` e ficava de fora sem motivo.
    def instrumento?
      sub = (catalogo&.props || {})['weapon_sub_category'].presence ||
            (item.props_json || {})['weapon_sub_category'].presence
      return true if sub.to_s == 'instrument'

      catalogo&.category.to_s == 'instrument'
    end

    # Vestuário — colar, máscara, tiara, broche. O cinto do aventureiro leva
    # quinquilharia; a peça vive em `Item.category` (ver `wardrobePropsPayload`).
    def vestuario?
      return false unless catalogo

      # Duas moradas, porque o catálogo guarda a PEÇA em sítios diferentes: a
      # base mundana em `category` (`gear`), o item mágico em `sub_category`.
      # Medido: 3 peças mundanas contra ~70 mágicas — só a primeira metade
      # deixaria quase todo o vestuário de fora.
      return true if catalogo.kind == 'gear' && WARDROBE_PIECES.include?(catalogo.category.to_s)

      catalogo.kind == 'magic_item' && WARDROBE_PIECES.include?(catalogo.sub_category.to_s)
    end

    def nome_normalizado
      @nome_normalizado ||= item.item_name.to_s.unicode_normalize(:nfd)
                                .gsub(/[\u0300-\u036f]/, '').downcase
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
      ocupados = presos.count { |si| self.class.slot_kind_for(si) == tipo }
      return if ocupados < total

      raise InvalidStow, "Sem vaga: #{ocupados}/#{total} slots #{tipo == 'free' ? 'livres' : 'de consumível'} ocupados."
    end

    # Tirar do cinto devolve à bolsa VESTIDA — é de lá que a mão tirou e é
    # para lá que arruma. Cai solto só quando não há bolsa vestida ou quando o
    # item já não cabe nela (a bolsa encheu enquanto ele estava no cinto); aí
    # o cabeçalho da ficha conta os soltos e diz onde vê-los.
    def soltar!
      props = (item.props_json || {}).deep_dup.stringify_keys
      props.delete(SheetItem::BELT_CONTAINER_PROP)
      props.delete(SheetItem::BAG_CONTAINER_PROP)

      bolsa = bolsa_vestida
      props[SheetItem::BAG_CONTAINER_PROP] = bolsa.id if bolsa&.bag_room_for?(item)

      # Funde na pilha gémea do destino: a poção que saiu do cinto volta a ser
      # "×3" na bolsa, e não uma segunda linha "×1" ao lado da "×2".
      gemea = pilha_gemea(props)
      if gemea
        gemea.update!(quantity: gemea.quantity.to_i + item.quantity.to_i)
        item.destroy!
        return
      end

      item.update!(props_json: props)
    end

    def pilha_gemea(destino)
      candidato = item.dup
      candidato.equipped = false
      candidato.slot = nil
      candidato.props_json = destino
      SheetItem.stackable_match_for(candidato)
    end

    def bolsa_vestida
      SheetItem.worn_bag_for(item.sheet)
    end

    def prender!(cinto, tipo)
      props = (item.props_json || {}).deep_dup.stringify_keys
      props[SheetItem::BELT_CONTAINER_PROP] = cinto.id
      # Preso no cinto não pode continuar noutro depósito: os ponteiros são
      # exclusivos entre si (o item está num lugar só).
      props.delete(SheetItem::BAG_CONTAINER_PROP)
      props.delete(SheetItem::BAG_SLOT_CONTAINER_PROP)

      # CONSUMÍVEL: o slot leva UMA unidade — é o frasco que a mão alcança, não
      # a caixa toda. Três poções na bolsa viram uma no cinto e duas onde
      # estavam; sem isto, um slot escondia a pilha inteira e beber esvaziava
      # tudo de uma vez. Arma e ferramenta não empilham, então a linha vai
      # inteira como sempre.
      if tipo == 'consumable' && item.quantity.to_i > 1
        preso = item.dup
        preso.quantity = 1
        preso.equipped = false
        preso.slot = nil
        preso.props_json = props
        preso.save!
        item.update!(quantity: item.quantity.to_i - 1)
        return
      end

      item.update!(props_json: props)
    end

    def inventario(sheet)
      sheet.sheet_items.includes(:item).order(:position, :id).map(&:as_inventory_json)
    end
  end
end
