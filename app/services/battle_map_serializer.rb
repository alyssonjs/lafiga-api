# Serializa um BattleMap no shape camelCase que o front consome direto
# (espelha a interface `BattleMap` em front-lafiga/src/app/data/mapData.ts).
#
# Modos:
# - :slim  — sem `cells/tokens/fog/backgroundImage` (listagem). Evita
#            payload de MBs em GET /battle_maps quando o usuario tem 30+ mapas
#            com background images base64.
# - :full  — payload completo (show, after-create, after-update).
#
# camelCase aqui (cellSizePx, gridOpacity, backgroundImage, schemaVersion,
# createdAt, updatedAt) e proposital: o front nao precisa de mapper extra.
class BattleMapSerializer
  def self.serialize(map, mode: :full)
    return nil unless map

    base = {
      id: map.id,
      name: map.name,
      width: map.width,
      height: map.height,
      cellSizePx: map.cell_size_px,
      gridOpacity: map.grid_opacity,
      schemaVersion: map.schema_version,
      userId: map.user_id,
      groupId: map.group_id,
      playerPermissions: map.player_permissions || BattleMap::DEFAULT_PLAYER_PERMISSIONS.dup,
      distanceDisplayUnit: map.distance_display_unit.presence || 'm',
      cellWorldFt: map.cell_world_ft.to_f,
      fogMode: map.fog_mode.presence || 'hidden_cells',
      createdAt: map.created_at&.iso8601,
      updatedAt: map.updated_at&.iso8601,
    }

    return base if mode == :slim

    base.merge(
      cells: map.cells || [],
      tokens: map.tokens || [],
      walls: map.walls || [],
      measurements: map.measurements || [],
      aoePlacements: map.aoe_placements || [],
      drawings: map.drawings || [],
      fog: map.fog,
      backgroundImage: map.background_image_url,
      backgroundImageOffsetX: map.background_image_offset_x,
      backgroundImageOffsetY: map.background_image_offset_y,
      backgroundImagePixelWidth: map.background_image_pixel_width,
      backgroundImagePixelHeight: map.background_image_pixel_height,
    )
  end

  def self.serialize_collection(maps, mode: :slim)
    maps.map { |m| serialize(m, mode: mode) }
  end
end
