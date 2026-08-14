# frozen_string_literal: true

# Sincroniza a customizacao canonica da ficha nos snapshots dos tokens que
# representam o personagem. Cada mapa e alterado por patch de campo sob lock;
# uma edicao de avatar nunca pode restaurar posicao/equipamento de outro cliente.
module BattleMapCharacterCustomization
  module_function

  def sync!(character:, actor: nil)
    customization = character.sheet&.avatar_customization
    return [] unless customization.is_a?(Hash) && customization.present?

    synced = []
    maps_for(character).find_each do |map|
      token_ids = Array(map.tokens).filter_map do |token|
        token_id = token['id'] || token[:id]
        linked_id = token['characterId'] || token[:characterId]
        token_id.to_s if token_id.present? && linked_id.to_s == character.id.to_s
      end
      next if token_ids.empty?

      result = BattleMapTokenMutations.call(
        map: map,
        allow_character_visuals: true,
        mutation: {
          patches: token_ids.map do |token_id|
            {
              token_id: token_id,
              changes: { chibiCustomization: customization.deep_stringify_keys },
            }
          end,
        },
      )
      next if result.mutation.values.all?(&:empty?)

      MapRealtime::Broadcaster.tokens_patched(
        map,
        result.mutation,
        version: result.version,
        actor: actor,
      )
      synced << map.id
    end
    synced
  end

  def maps_for(character)
    BattleMap.where(
      "EXISTS (SELECT 1 FROM jsonb_array_elements(battle_maps.tokens) AS token " \
      "WHERE token->>'characterId' = ?)",
      character.id.to_s,
    )
  end
  private_class_method :maps_for
end
