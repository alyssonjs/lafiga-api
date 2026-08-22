# frozen_string_literal: true

# Rebuilds the token hand-equipment snapshot from the persisted SheetItems.
# The database is the only authority: callers never send a browser snapshot.
module BattleMapTokenEquipment
  HAND_SLOTS = %w[main_hand off_hand shield].freeze

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
         .where(equipped: true, slot: HAND_SLOTS)
         .order(:position, :id)
         .map { |item| snapshot_item(item) }
  end

  def snapshot_item(item)
    weapon_props = EquipmentRules.weapon_props(item)
    {
      'id' => item.id.to_s,
      'refId' => item.item_index,
      'name' => item.item_name,
      'category' => item.category,
      'quantity' => item.quantity,
      'equipped' => true,
      'slot' => item.slot,
      'weaponProps' => weapon_props&.deep_stringify_keys,
      'magical' => ActiveModel::Type::Boolean.new.cast((item.props_json || {})['magical']),
      'magicBonus' => (item.props_json || {})['magic_bonus'],
      'rarity' => (item.props_json || {})['rarity'],
      'weaponSubCategory' => (item.props_json || {})['weapon_sub_category'],
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
