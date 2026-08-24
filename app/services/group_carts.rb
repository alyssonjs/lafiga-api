# frozen_string_literal: true

# Depósitos móveis do grupo (carroça, carruagem, vagão…).
#
# O item NUNCA muda de dono: ele fica na ficha de quem comprou e só aponta para
# a carroça (`sheet_items.props_json['cart_id']`). É isso que dá "de quem é cada
# item" sem transferência nenhuma — o `sheet_id` sempre foi a resposta.
module GroupCarts
  # Chave em `props_json` que põe o item na carroça.
  CONTAINER_PROP = 'cart_id'

  module_function

  def all(group)
    Array(group&.carts).select { |c| c.is_a?(Hash) }
  end

  def find(group, cart_id)
    all(group).find { |c| c['id'].to_s == cart_id.to_s }
  end

  def mounts_of(cart)
    Array(cart&.dig('mounts')).select { |m| m.is_a?(Hash) }
  end

  # Capacidade pela regra do PHB (pg. 155): "um animal puxando carruagem,
  # carroça, biga ou trenó carrega até CINCO VEZES sua capacidade básica,
  # INCLUINDO o peso do veículo. Se vários animais puxarem, eles SOMAM."
  #
  # Sem animal atrelado a capacidade é ZERO — carroça parada não carrega nada,
  # e é a regra que diz isso, não uma escolha nossa.
  MULTIPLIER = 5

  def capacity_lb(group, cart)
    bruta = mounts_of(cart).sum { |m| mount_capacity(group, m) } * MULTIPLIER
    peso_veiculo = cart['weight_lb'].to_f
    [bruta - peso_veiculo, 0].max
  end

  # Capacidade básica do animal, lida do companion na ficha DELE — as montarias
  # que puxam a carroça do grupo pertencem a personagens diferentes.
  #
  # É a capacidade BÁSICA de propósito: alforje aumenta o que a montaria leva
  # às costas, não a força com que puxa.
  def mount_capacity(group, ref)
    companion = companion_for(group, ref)
    companion ? companion['carryCapacity'].to_f : 0
  end

  def mount_name(group, ref)
    companion_for(group, ref)&.dig('name')
  end

  def companion_for(group, ref)
    sheet = group&.characters&.find { |c| c.sheet&.id.to_s == ref['sheet_id'].to_s }&.sheet
    return nil unless sheet

    Array(sheet.companions).find { |c| c.is_a?(Hash) && c['id'].to_s == ref['companion_id'].to_s }
  end

  # Peso unitário, em libras. Preferência: `props_json['weight_lb']` gravado na
  # instância; sem ele, cai no peso do CATÁLOGO (kg x 2, convenção do livro).
  # Antes o fallback não existia e item guardado sem prop pesava 0 na carroça —
  # carga de graça. (O comentário antigo dizia que o catálogo guardava libras;
  # era falso: `items.weight_kg` guarda kg do PHB pt-BR.)
  def item_weight_lb(sheet_item)
    bruto = (sheet_item.props_json || {})['weight_lb']
    return bruto.to_f unless bruto.nil?

    EquipmentRules.item_weight_lb(sheet_item).to_f
  rescue NameError
    0.0
  end

  # Todos os `sheet_items` desta carroça, de TODAS as fichas do grupo.
  def items(group, cart_id)
    sheet_ids = group.characters.filter_map { |c| c.sheet&.id }
    return SheetItem.none if sheet_ids.empty?

    SheetItem
      .includes(:item, sheet: :character)
      .where(sheet_id: sheet_ids)
      .where("props_json ->> '#{CONTAINER_PROP}' = ?", cart_id.to_s)
      .order(:item_name)
  end

  # Solta o conteúdo: apaga só o ponteiro, mantendo cada item na ficha do dono.
  # Mesma garantia da aljava e da montaria — destruir o recipiente não pode
  # evaporar o que estava dentro.
  def release!(group, cart_id)
    items(group, cart_id).find_each do |si|
      props = (si.props_json || {}).dup
      props.delete(CONTAINER_PROP)
      si.update!(props_json: props)
    end
  end
end
