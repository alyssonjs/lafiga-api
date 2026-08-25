# Serializa um BattleMap no shape camelCase que o front consome direto
# (espelha a interface `BattleMap` em front-lafiga/src/app/data/mapData.ts).
#
# Modos:
# - :slim   — sem `cells/tokens/fog/backgroundImage` (listagem). Evita
#             payload de MBs em GET /battle_maps quando o usuario tem 30+ mapas
#             com background images base64. Tambem serve de resposta de #update
#             (o front descarta o corpo — a verdade vem do broadcast/otimista).
# - :tokens — base + apenas `tokens` (SEM cells/fog/background/layers). Resposta
#             do hot path #move_token: o front reconcilia so `battle_map.tokens`,
#             entao evitamos serializar o base64 do fundo + a matriz de 40k cells
#             que o cliente descartaria a cada arrasto.
# - :full   — payload completo (show, after-create, after-duplicate).
#
# camelCase aqui (cellSizePx, gridOpacity, backgroundImage, schemaVersion,
# createdAt, updatedAt) e proposital: o front nao precisa de mapper extra.
class BattleMapSerializer
  # `session_layer` (um ScheduleBattleMap) = estado de MESA daquela sessão.
  # Quando presente, o payload mistura o TABULEIRO (do mapa) com a camada da
  # sessão: tokens de criatura, névoa, medidas, desenhos, AoE e projéteis vêm
  # dela. Sem ele (Map Builder, listagem) o mapa responde sozinho, como antes.
  def self.serialize(map, mode: :full, session_layer: nil)
    return nil unless map

    base = {
      id: map.id,
      name: map.name,
      width: map.width,
      height: map.height,
      cellSizePx: map.cell_size_px,
      gridOpacity: map.grid_opacity,
      # Opacidade das LINHAS da grade (0 = invisivel). Distinto do gridOpacity,
      # que — apesar do nome — e o veu de TERRENO sobre a arte.
      gridLinesOpacity: map.grid_lines_opacity,
      schemaVersion: map.schema_version,
      userId: map.user_id,
      groupId: map.group_id,
      playerPermissions: map.player_permissions || BattleMap::DEFAULT_PLAYER_PERMISSIONS.dup,
      distanceDisplayUnit: map.distance_display_unit.presence || 'm',
      cellWorldFt: map.cell_world_ft.to_f,
      fogMode: map.fog_mode.presence || 'hidden_cells',
      mapKind: map.map_kind.presence || 'battle',
      createdAt: map.created_at&.iso8601,
      updatedAt: map.updated_at&.iso8601,
      # Miniatura LEVE do fundo (data URI webp ~400px, gerada client-side no upload).
      # Vai também no :slim → a LISTA de mapas renderiza a miniatura sem baixar o
      # fundo FULL de cada mapa (que antes forçava um GET :full por card, de MBs).
      backgroundThumbnail: map.try(:background_thumbnail),
    }

    return base if mode == :slim

    # :tokens — base + só o array de tokens. Mantém o único campo que o
    # #move_token do front consome, sem o peso de cells/fog/background/layers.
    return base.merge(tokens: tokens_for(map, session_layer)) if mode == :tokens

    base.merge(
      cells: map.cells || [],
      # O snapshot visual gravado no token pode ter sido criado antes da ultima
      # edicao do personagem. No carregamento FULL, a ficha e a fonte canonica:
      # isso corrige mapas legados sem transformar um GET em escrita no JSONB.
      tokens: tokens_with_current_customizations(map, session_layer),
      walls: map.walls || [],
      measurements: layer_value(session_layer, :measurements, map.measurements) || [],
      aoePlacements: layer_value(session_layer, :aoe_placements, map.aoe_placements) || [],
      drawings: layer_value(session_layer, :drawings, map.drawings) || [],
      fog: session_layer ? session_layer.fog : map.fog,
      backgroundImage: background_image_src(map),
      backgroundImageOffsetX: map.background_image_offset_x,
      backgroundImageOffsetY: map.background_image_offset_y,
      backgroundImagePixelWidth: map.background_image_pixel_width,
      backgroundImagePixelHeight: map.background_image_pixel_height,
      # Fase 2.0 — camadas do Map Builder (só no :full; listagem :slim não
      # carrega para não inflar o GET de listas).
      layers: map.layers || [],
      terrainLayers: map.terrain_layers || [],
      stamps: map.stamps || [],
      paths: map.paths || [],
      mapEffects: map.map_effects || {},
      droppedProjectiles: layer_value(session_layer, :dropped_projectiles, map.dropped_projectiles) || [],
    )
  end

  def self.serialize_collection(maps, mode: :slim)
    maps.map { |m| serialize(m, mode: mode) }
  end

  # Tabuleiro (cenário do mapa) + criaturas da mesa. Sem camada, o mapa
  # responde sozinho — é o caminho do Map Builder e da listagem.
  def self.tokens_for(map, session_layer)
    return map.tokens || [] unless session_layer

    map.scenery_tokens + Array(session_layer.tokens)
  end

  def self.layer_value(session_layer, field, fallback)
    session_layer ? session_layer.public_send(field) : fallback
  end

  def self.tokens_with_current_customizations(map, session_layer = nil)
    # Parte do conjunto JÁ mesclado (tabuleiro + mesa) — a customização vale
    # tanto para o cenário quanto para as criaturas da sessão.
    tokens = Array(tokens_for(map, session_layer)).map(&:deep_dup)
    character_ids = tokens.filter_map do |token|
      raw = token['characterId'] || token[:characterId]
      raw.to_s if raw.present?
    end.uniq
    return tokens if character_ids.empty?

    characters_by_id = Character
      .where(id: character_ids)
      .includes(sheet: { sheet_items: :item })
      .each_with_object({}) do |character, out|
        out[character.id.to_s] = character
      end

    tokens.each do |token|
      character_id = (token['characterId'] || token[:characterId]).to_s
      character = characters_by_id[character_id]
      next unless character

      customization = character.sheet&.avatar_customization
      token['chibiCustomization'] = customization.deep_dup if customization
      token['chibiEquipment'] = BattleMapTokenEquipment.snapshot_for(character)
    end
    tokens
  end
  private_class_method :tokens_with_current_customizations

  # Purpose do verificador do fundo — DEVE bater com o do controller
  # (Api::V1::Player::BattleMapsController#valid_background_sig?).
  BACKGROUND_SIG_PURPOSE = 'battle_map_background'

  # Fonte do fundo p/ o front (:full). Se há blob no Active Storage → path RELATIVO
  # do endpoint assinado (o front prefixa com apiBaseUrl, igual a mapAssetImageUrl).
  # Senão → coluna text legada (base64) p/ mapas ainda não migrados pelo backfill.
  # `sig` = assinatura do blob.id (autz do endpoint, sem IDOR); `v=blob.id` reforça
  # o cache-bust ao trocar o fundo. CGI.escape no sig (base64 tem +/=, inseguros em URL).
  def self.background_image_src(map)
    return map.background_image_url unless map.respond_to?(:background_image) && map.background_image.attached?

    blob = map.background_image.blob
    sig = Rails.application.message_verifier(BACKGROUND_SIG_PURPOSE).generate(blob.id)
    "/api/v1/player/battle_maps/#{map.id}/background?v=#{blob.id}&sig=#{CGI.escape(sig)}"
  end
end
