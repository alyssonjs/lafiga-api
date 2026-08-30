# frozen_string_literal: true

module SheetItems
  # Guarda um item DENTRO de uma bolsa da mesma ficha (ou tira: bag_id nulo).
  #
  # Mesmo desenho do StowOnMountService/StowInCartService: o item nunca muda de
  # dono — a localização é o ponteiro `bag_sheet_item_id`. Duas regras são
  # DESTE depósito, e por isso o serviço existe:
  #
  #  1. CAPACIDADE em KG, do catálogo: a soma do conteúdo não passa do teto.
  #     Validada AQUI porque duas abas abertas guardariam o mesmo último quilo
  #     se só o cliente somasse.
  #  2. CICLO: bolsa dentro de bolsa é permitido (é o pedido), mas A dentro de
  #     B dentro de A viraria um buraco negro — quem caminha a corrente é o
  #     servidor, com as linhas travadas.
  class StowInBagService
    class InvalidStow < StandardError; end

    # `quantity` nulo = a pilha INTEIRA (o que sempre foi). Com número, move
    # só parte: 3 das 10 flechas passam para a outra bolsa e 7 ficam onde
    # estavam. A divisão é a mesma do StowOnMountService — funde na pilha
    # gémea do destino se já existir lá uma igual, senão nasce linha nova.
    def initialize(item:, bag_id:, quantity: nil)
      @item = item
      @bag_id = bag_id.presence
      @quantity = quantity.presence&.to_i
    end

    def call
      sheet = item.sheet
      sheet.with_lock do
        item.lock!
        validar_quantidade!

        if bag_id.nil?
          mover!(sheet, nil)
        else
          bolsa = achar_bolsa!(sheet)
          validar_nao_e_a_propria!(bolsa)
          validar_sem_ciclo!(sheet, bolsa)
          validar_capacidade!(sheet, bolsa)
          mover!(sheet, bolsa)
        end

        # Devolve o INVENTÁRIO, não a linha: um movimento parcial toca duas
        # (a que ficou e a que nasceu), e a linha original pode nem existir
        # depois — mover a pilha inteira para uma gémea destrói-a.
        return inventario(sheet)
      end
    end

    private

    attr_reader :item, :bag_id

    # Quantidade a mover: o pedido, ou a pilha inteira quando não vem nenhum.
    def quantidade
      @quantidade ||= (@quantity || item.quantity.to_i)
    end

    def validar_quantidade!
      return if quantidade.positive? && quantidade <= item.quantity.to_i

      raise InvalidStow, "Quantidade inválida. Disponível: #{item.quantity.to_i}"
    end

    # Props que o item passa a ter no destino (bolsa nula = fora de qualquer uma).
    def props_para(bolsa)
      props = (item.props_json || {}).deep_dup.stringify_keys
      props.delete(SheetItem::BAG_CONTAINER_PROP)
      props[SheetItem::BAG_CONTAINER_PROP] = bolsa.id if bolsa
      props
    end

    # Pilha gémea já no destino: mesmo item, mesmas props de empilhamento.
    def pilha_gemea(destino)
      candidato = item.dup
      candidato.quantity = quantidade
      candidato.equipped = false
      candidato.slot = nil
      candidato.props_json = destino
      SheetItem.stackable_match_for(candidato)
    end

    def mover!(_sheet, bolsa)
      destino = props_para(bolsa)
      gemea = pilha_gemea(destino)

      # Pilha inteira e sem gémea onde fundir: só reetiqueta, sem criar linha.
      if quantidade == item.quantity.to_i && gemea.nil?
        item.update!(props_json: destino)
        return
      end

      if gemea
        gemea.update!(quantity: gemea.quantity.to_i + quantidade)
      else
        movido = item.dup
        movido.quantity = quantidade
        movido.equipped = false
        movido.slot = nil
        movido.props_json = destino
        movido.save!
      end

      restante = item.quantity.to_i - quantidade
      restante.positive? ? item.update!(quantity: restante) : item.destroy!
    end

    def achar_bolsa!(sheet)
      bolsa = sheet.sheet_items.lock.find_by(id: bag_id)
      raise InvalidStow, 'A bolsa não pertence a esta ficha.' unless bolsa
      raise InvalidStow, 'O destino não é uma bolsa.' unless bolsa.bag?

      bolsa
    end

    def validar_nao_e_a_propria!(bolsa)
      raise InvalidStow, 'Uma bolsa não cabe dentro de si mesma.' if bolsa.id == item.id
    end

    # Sobe a corrente de continentes a partir da BOLSA DESTINO: se em algum
    # ponto ela estiver dentro do próprio item guardado, é ciclo.
    def validar_sem_ciclo!(sheet, bolsa)
      visitados = Set.new([item.id])
      atual = bolsa
      passos = 0
      while atual
        raise InvalidStow, 'Isso criaria uma bolsa dentro dela mesma (ciclo).' if visitados.include?(atual.id)

        visitados << atual.id
        pai_id = atual.stored_in_bag_id
        break if pai_id.blank?

        # Corrente comprida demais é sinal de dado podre, não de mochileiro.
        passos += 1
        raise InvalidStow, 'Corrente de bolsas comprida demais.' if passos > 10

        atual = sheet.sheet_items.find_by(id: pai_id)
      end
    end

    # Peso em KG (canônico do banco) do que JÁ está na bolsa + o candidato.
    # Teto 0 = bolsa sem capacidade declarada (manual do mestre): sem limite.
    def validar_capacidade!(sheet, bolsa)
      teto = bolsa.bag_capacity_kg
      return if teto <= 0

      conteudo = sheet.sheet_items
                      .where("props_json ->> '#{SheetItem::BAG_CONTAINER_PROP}' = ?", bolsa.id.to_s)
                      .where.not(id: item.id)
      atual = conteudo.sum { |si| peso_kg(si) }
      novo = atual + peso_unitario_kg(item) * quantidade
      return if novo <= teto + 0.0001

      raise InvalidStow,
            "Não cabe: #{novo.round(2)} kg num teto de #{teto.round(2)} kg."
    end

    def peso_kg(si)
      peso_unitario_kg(si) * (si.quantity || 1).to_i
    end

    def inventario(sheet)
      sheet.sheet_items.includes(:item).order(:position, :id).map(&:as_inventory_json)
    end

    def peso_unitario_kg(si)
      EquipmentRules.item_weight_kg(si).to_f
    rescue StandardError
      0.0
    end
  end
end
