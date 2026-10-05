# frozen_string_literal: true

# Rebuilds the token equipment snapshot from the persisted SheetItems.
# The database is the only authority: callers never send a browser snapshot.
module BattleMapTokenEquipment
  HAND_SLOTS = %w[main_hand off_hand shield].freeze
  # O que o personagem LPC do mapa VESTE (02/10): sem estes na foto, os outros jogadores — que não têm a ficha —
  # veriam o personagem sem armadura. As mãos continuam sendo o que o chibi lê (ele escolhe pelo slot).
  VISUAL_SLOTS = %w[armor boots clothing cloak helmet gloves belt].freeze
  SNAPSHOT_SLOTS = (HAND_SLOTS + VISUAL_SLOTS).freeze

  module_function

  def sync!(map:, character:, **_legacy_args)
    changes = []
    snapshot = snapshot_for(character)

    map.with_lock do
      map.reload
      # Estado de MESA: com sessao marcada na instancia do mapa, a sincronia do
      # equipamento altera o token daquela sessao, nao o de todas as mesas.
      layer = MapSessionLayer.for(map: map, schedule_id: map.session_scope_schedule_id)
      tokens = Array(layer.tokens).map(&:deep_dup)
      tokens.each do |token|
        next unless token['characterId'].to_s == character.id.to_s
        next if Array(token['chibiEquipment']) == snapshot && token.key?('chibiEquipment')

        token['chibiEquipment'] = snapshot
        changes << { token_id: token['id'].to_s, chibi_equipment: snapshot }
      end
      layer.update!(tokens: tokens) if changes.any?
    end

    changes
  end

  def snapshot_for(character)
    sheet = character&.sheet
    return [] unless sheet

    sheet.sheet_items
         .includes(:item)
         .where(equipped: true, slot: SNAPSHOT_SLOTS)
         .order(:position, :id)
         .map { |item| snapshot_item(item) }
  end

  def snapshot_item(item)
    weapon_props = EquipmentRules.weapon_props(item)
    props = item.props_json || {}
    {
      'id' => item.id.to_s,
      'refId' => item.item_index,
      'name' => item.item_name,
      'category' => item.category,
      'quantity' => item.quantity,
      'equipped' => true,
      'slot' => item.slot,
      'weaponProps' => weapon_props&.deep_stringify_keys,
      'magical' => ActiveModel::Type::Boolean.new.cast(props['magical']),
      'magicBonus' => props['magic_bonus'],
      'rarity' => props['rarity'],
      'weaponSubCategory' => props['weapon_sub_category'],
      'lpcPecas' => EquipmentRules.lpc_pecas(item),
      # A EMPUNHADURA da arma versátil (03/10): o personagem LPC do mapa ataca com uma ou duas mãos. Três estados,
      # como no front (`versatileGripRuntime`): true, false ou AUSENTE (nunca escolheu) — o `compact` tira o ausente.
      'usingTwoHands' => props.key?('using_two_hands') ? ActiveModel::Type::Boolean.new.cast(props['using_two_hands']) : nil,
    }.compact
  rescue StandardError
    {
      'id' => item.id.to_s,
      'refId' => item.item_index,
      'name' => item.item_name,
      'category' => item.category,
      'quantity' => item.quantity,
      'equipped' => true,
      'slot' => item.slot,
    }.compact
  end
  private_class_method :snapshot_item
end
