class Api::V1::Player::BattleMapsController < ApplicationController
  before_action :authorize_request
  before_action :set_map, only: [:show, :update, :destroy, :duplicate, :move_token]

  # GET /api/v1/player/battle_maps
  # Lista todos os mapas que o user pode ver: proprios + compartilhados via group.
  # Retorna no shape SLIM (sem cells/tokens/fog/backgroundImage) — abrir um mapa
  # individual via GET /:id traz o payload full.
  def index
    maps = BattleMap.visible_to(@current_user).recent
    render json: { battle_maps: BattleMapSerializer.serialize_collection(maps, mode: :slim) }, status: 200
  end

  def show
    return forbidden unless @map.readable_by?(@current_user)
    render json: { battle_map: BattleMapSerializer.serialize(@map, mode: :full) }, status: 200
  end

  # POST /api/v1/player/battle_maps
  # DM pode criar mapas livremente; Player tambem pode criar (so seus proprios)
  # — quem joga sem DM ainda quer rascunhar mapas.
  def create
    map = BattleMap.new(write_attributes.merge(user_id: @current_user.id))
    if map.save
      render json: { battle_map: BattleMapSerializer.serialize(map, mode: :full) }, status: :created
    else
      render json: { errors: map.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    attrs = write_attributes

    # Fase E5: players podem atualizar APENAS measurements/drawings se a
    # permissao estiver ligada e nao mexerem em nenhum outro campo. Owner/DM
    # cai no caminho normal (writable_by?).
    if @map.writable_by?(@current_user)
      # Owner/DM: permitido tudo.
    else
      return forbidden unless @map.readable_by?(@current_user)

      tool_keys = attrs.keys.map(&:to_s)
      allowed_keys = []
      allowed_keys << 'measurements' if @map.players_can?('measure')
      allowed_keys << 'drawings'     if @map.players_can?('pencil')
      allowed_keys << 'aoe_placements' if @map.players_can?('aoe')
      forbidden_keys = tool_keys - allowed_keys
      return forbidden unless forbidden_keys.empty?
      return forbidden if attrs.empty?

      if attrs.key?(:aoe_placements) && attrs[:aoe_placements].is_a?(Array) && !@map.writable_by?(@current_user)
        old = @map.aoe_placements || []
        new_list = attrs[:aoe_placements]
        old_ids = old.map { |p| (p['id'] || p[:id]).to_s }.compact.to_set
        new_ids = new_list.map { |p| (p['id'] || p[:id]).to_s }.compact.to_set
        return forbidden unless old_ids <= new_ids
      end
    end

    if @map.update(attrs)
      broadcast_update_diffs
      render json: { battle_map: BattleMapSerializer.serialize(@map, mode: :full) }, status: 200
    else
      render json: { errors: @map.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    return forbidden unless @map.writable_by?(@current_user)
    map_id = @map.id
    @map.destroy
    MapRealtime::Broadcaster.map_deleted(map_id, actor: @current_user)
    render json: { message: 'Mapa removido com sucesso' }, status: 200
  end

  # POST /api/v1/player/battle_maps/:id/duplicate
  # Deep copy. Util para template -> personalizar.
  def duplicate
    return forbidden unless @map.readable_by?(@current_user)
    copy = @map.dup
    copy.user_id = @current_user.id
    copy.name = "#{@map.name} (Copia)"
    copy.cells = deep_dup_array(@map.cells)
    copy.tokens = deep_dup_array(@map.tokens)
    copy.fog = @map.fog.nil? ? nil : deep_dup_array(@map.fog)
    if copy.save
      render json: { battle_map: BattleMapSerializer.serialize(copy, mode: :full) }, status: :created
    else
      render json: { errors: copy.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/player/battle_maps/import_legacy
  # Aceita { battle_maps: [BattleMap...] } vindo do localStorage do front. E
  # idempotente por (user_id + name + createdAt) — re-rodar nao duplica.
  # Marca todos com user_id = current_user.
  def import_legacy
    raw = params[:battle_maps] || []
    raw = raw.is_a?(ActionController::Parameters) ? raw.to_unsafe_h.values : raw
    return render(json: { imported: [], skipped: [] }, status: 200) unless raw.is_a?(Array)

    imported = []
    skipped = []

    BattleMap.transaction do
      raw.each do |item|
        normalized = normalize_legacy_payload(item)
        next unless normalized

        legacy_created_at = parse_iso(normalized[:created_at_iso])

        # Idempotencia: mesmo (user, name, created_at) -> ja importado.
        # Como persistimos created_at do payload, comparacao bate em re-runs.
        if legacy_created_at
          existing = BattleMap.find_by(
            user_id: @current_user.id,
            name: normalized[:name],
            created_at: legacy_created_at,
          )
          if existing
            skipped << existing.id
            next
          end
        end

        attrs = normalized[:attrs].merge(user_id: @current_user.id)
        attrs[:created_at] = legacy_created_at if legacy_created_at
        attrs[:updated_at] = parse_iso(normalized[:updated_at_iso]) || legacy_created_at if legacy_created_at

        map = BattleMap.new(attrs)
        if map.save
          imported << BattleMapSerializer.serialize(map, mode: :slim)
        end
      end
    end

    render json: { imported: imported, skipped_count: skipped.size }, status: 200
  end

  # POST /api/v1/player/battle_maps/:id/move_token
  # Mover token e a operacao mais quente da sessao. Endpoint dedicado evita
  # PATCH do array tokens inteiro a cada arrasto (latencia + bandwidth).
  #
  # Authorization especial:
  # - DM pode mover qualquer token.
  # - Player so pode mover token cujo characterId e de um proprio Character.
  # - Token sem characterId (NPC efemero, marcador) so DM pode mexer.
  def move_token
    return forbidden unless @map.readable_by?(@current_user)
    token_id = params[:token_id].to_s
    new_x = params[:x].to_i
    new_y = params[:y].to_i

    tokens = Array(@map.tokens)
    idx = tokens.index { |t| (t['id'] || t[:id]).to_s == token_id }
    return render(json: { error: 'Token nao encontrado' }, status: :not_found) unless idx

    token = tokens[idx]
    character_id = token['characterId'] || token[:characterId]

    unless Group.user_is_dm?(@current_user)
      owns = character_id.present? && @current_user.characters.exists?(id: character_id.to_s)
      return forbidden unless owns
    end

    size = (token['size'] || token[:size] || 1).to_i
    if new_x < 0 || new_y < 0 || new_x + size > @map.width || new_y + size > @map.height
      return render(json: { error: 'Posicao fora dos limites' }, status: :unprocessable_entity)
    end

    token = token.merge('x' => new_x, 'y' => new_y)
    tokens[idx] = token
    @map.update!(tokens: tokens)

    MapRealtime::Broadcaster.token_moved(@map, token_id, new_x, new_y, actor: @current_user)
    render json: { battle_map: BattleMapSerializer.serialize(@map, mode: :full) }, status: 200
  end

  private

  def set_map
    @map = BattleMap.find_by(id: params[:id])
    render(json: { error: 'Mapa nao encontrado' }, status: :not_found) unless @map
  end

  def forbidden
    render(json: { error: 'Sem permissao' }, status: :forbidden)
  end

  # Strong params nao suporta nested arrays (cells e [[String]], tokens e
  # [Hash]). Permitimos os escalares via permit() e copiamos cells/tokens/fog
  # do raw payload via to_unsafe_h. Validacao de shape vive no model.
  def write_attributes
    raw = params.require(:battle_map)
    permitted = raw.permit(
      :name, :width, :height, :cell_size_px, :group_id,
      :background_image_url, :background_image_offset_x, :background_image_offset_y,
      :grid_opacity, :schema_version, :distance_display_unit, :cell_world_ft,
      :fog_mode,
    ).to_h

    unsafe = raw.to_unsafe_h.with_indifferent_access
    permitted[:cells]        = unsafe[:cells]        if unsafe.key?(:cells)
    permitted[:tokens]       = unsafe[:tokens]       if unsafe.key?(:tokens)
    permitted[:walls]        = unsafe[:walls]        if unsafe.key?(:walls)
    permitted[:fog]          = unsafe[:fog]          if unsafe.key?(:fog)
    permitted[:measurements]       = unsafe[:measurements]       if unsafe.key?(:measurements)
    permitted[:aoe_placements]     = unsafe[:aoe_placements]     if unsafe.key?(:aoe_placements)
    permitted[:drawings]           = unsafe[:drawings]           if unsafe.key?(:drawings)
    permitted[:player_permissions] = unsafe[:player_permissions] if unsafe.key?(:player_permissions)
    permitted
  end

  def deep_dup_array(arr)
    return [] if arr.nil?
    arr.map do |row|
      row.is_a?(Array) ? row.dup : (row.respond_to?(:deep_dup) ? row.deep_dup : row.dup)
    end
  end

  def normalize_legacy_payload(item)
    h = item.is_a?(ActionController::Parameters) ? item.to_unsafe_h : item
    return nil unless h.is_a?(Hash)
    h = h.transform_keys(&:to_s)
    return nil if h['name'].blank? || h['width'].nil? || h['height'].nil?

    {
      name: h['name'],
      created_at_iso: h['createdAt'],
      updated_at_iso: h['updatedAt'],
      attrs: {
        name: h['name'],
        width: h['width'].to_i,
        height: h['height'].to_i,
        cell_size_px: (h['cellSizePx'] || 32).to_i,
        cells: h['cells'] || [],
        tokens: h['tokens'] || [],
        fog: h['fog'],
        background_image_url: h['backgroundImage'],
        grid_opacity: h['gridOpacity'],
        schema_version: (h['schemaVersion'] || 1).to_i,
        distance_display_unit: %w[ft m].include?(h['distanceDisplayUnit'].to_s) ? h['distanceDisplayUnit'].to_s : 'm',
        cell_world_ft: normalize_legacy_cell_world_ft(h['cellWorldFt']),
        aoe_placements: h['aoePlacements'].is_a?(Array) ? h['aoePlacements'] : [],
      },
    }
  end

  def parse_iso(str)
    return nil if str.blank?
    Time.iso8601(str)
  rescue ArgumentError
    nil
  end

  def normalize_legacy_cell_world_ft(raw)
    v = raw.nil? ? 5.0 : raw.to_f
    BattleMap::ALLOWED_CELL_WORLD_FT.include?(v) ? v : 5.0
  end

  # Emite eventos granulares no MapChannel inspecionando previous_changes do
  # PATCH. Para alteracoes pequenas (so tokens, so cells, so fog) emitimos
  # so o evento especifico — assim front aplica diff em vez de re-renderizar
  # o mapa inteiro. Para mudancas estruturais (width/height/name) emitimos
  # `map_updated` com payload full.
  def broadcast_update_diffs
    changes = @map.previous_changes
    structural = (changes.keys & %w[name width height cell_size_px background_image_url grid_opacity group_id walls distance_display_unit cell_world_ft fog_mode]).any?

    if structural
      payload = BattleMapSerializer.serialize(@map, mode: :full)
      MapRealtime::Broadcaster.map_updated(@map, payload, actor: @current_user)
      return
    end

    MapRealtime::Broadcaster.tokens_changed(@map, @map.tokens, actor: @current_user)             if changes.key?('tokens')
    MapRealtime::Broadcaster.cells_changed(@map, @map.cells, actor: @current_user)               if changes.key?('cells')
    MapRealtime::Broadcaster.fog_changed(@map, @map.fog, actor: @current_user)                   if changes.key?('fog')
    MapRealtime::Broadcaster.measurements_changed(@map, @map.measurements, actor: @current_user) if changes.key?('measurements')
    MapRealtime::Broadcaster.aoe_placements_changed(@map, @map.aoe_placements, actor: @current_user) if changes.key?('aoe_placements')
    MapRealtime::Broadcaster.drawings_changed(@map, @map.drawings, actor: @current_user)         if changes.key?('drawings')
  rescue StandardError => e
    Rails.logger.warn("[BattleMapsController#broadcast_update_diffs] #{e.class}: #{e.message}")
  end
end
