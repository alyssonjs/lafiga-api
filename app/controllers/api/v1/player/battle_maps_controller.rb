class Api::V1::Player::BattleMapsController < ApplicationController
  before_action :authorize_request
  # `background` serve a imagem do fundo p/ <img>/new Image() — sem header de auth
  # possível. A autorização é pelo `sig` (signed_id do blob) presente na URL que só
  # o viewer autorizado recebeu no payload :full. Ver #background / #valid_background_sig?.
  skip_before_action :authorize_request, only: :background, raise: false
  before_action :set_map, only: [:show, :update, :destroy, :duplicate, :thumbnail, :move_token, :mutate_tokens, :launch_projectile, :resolve_projectile, :pick_up_projectile]

  # Teto p/ a miniatura inline (webp ~400px). Protege o payload :slim da lista de
  # inflar caso alguém mande algo grande demais como "thumbnail".
  MAX_THUMBNAIL_BYTES = 300 * 1024

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

  # GET /api/v1/player/battle_maps/:id/background?sig=<blob signed_id>
  # Serve o blob do fundo p/ <img>/new Image() (sem header de auth possível). A
  # autorização é pelo `sig`: só quem recebeu o payload :full autorizado do mapa
  # tem o signed_id do blob (inadivinhável) — o id sequencial do mapa não basta,
  # então não há IDOR. Cache PRIVADO (mapa é por-grupo); `sig` muda quando o blob
  # muda (novo fundo) → seguro cachear no browser. Ação pública (sem authorize_request).
  def background
    map = BattleMap.with_attached_background_image.find_by(id: params[:id])
    return head(:not_found) unless map&.background_image&.attached?

    blob = map.background_image.blob
    return head(:forbidden) unless valid_background_sig?(blob, params[:sig])

    expires_in 1.year, public: false
    response.cache_control[:extras] = ['immutable']
    send_data blob.download,
              type: blob.content_type || 'application/octet-stream',
              disposition: 'inline'
  end

  # POST /api/v1/player/battle_maps
  # DM pode criar mapas livremente; Player tambem pode criar (so seus proprios)
  # — quem joga sem DM ainda quer rascunhar mapas.
  def create
    map = BattleMap.new(write_attributes.merge(user_id: @current_user.id))
    if map.save
      apply_background!(map)
      render json: { battle_map: BattleMapSerializer.serialize(map, mode: :full) }, status: :created
    else
      render json: { errors: map.errors.full_messages }, status: :unprocessable_entity
    end

  end

  # POST /api/v1/player/battle_maps/:id/mutate_tokens
  # DM-only field-level mutation for additions/removals, multi-token movement,
  # object transforms and token metadata. Single player movement remains on the
  # narrower #move_token endpoint.
  def mutate_tokens
    return forbidden unless @map.writable_by?(@current_user)

    result = BattleMapTokenMutations.call(
      map: @map,
      mutation: params[:token_mutation] || {},
    )
    unless result.mutation.values.all?(&:empty?)
      MapRealtime::Broadcaster.tokens_patched(
        @map,
        result.mutation,
        version: result.version,
        actor: @current_user,
      )
    end

    render json: {
      battle_map: BattleMapSerializer.serialize(@map, mode: :tokens),
      token_mutation: {
        additions: result.mutation[:additions],
        patches: result.mutation[:patches].map do |patch|
          {
            tokenId: patch[:token_id],
            changes: patch[:changes],
            unset: patch[:unset],
          }
        end,
        deleteIds: result.mutation[:delete_ids],
        version: result.version,
      },
    }, status: :ok
  rescue BattleMapTokenMutations::Invalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
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
        new_ids = new_list.map { |p| (p['id'] || p[:id]).to_s }.compact.to_set
        # Jogador (nao-owner) pode ADICIONAR qualquer placement e REMOVER apenas os
        # EFEMEROS — marcadores transitorios das proprias magias de area, que o front
        # limpa ao resolver a magia (ex.: Onda Trovejante com `ephemeral: true`).
        # Placements PERSISTENTES (colocados pelo DM/owner) seguem append-only: nao
        # podem ser removidos por jogador. O flag `ephemeral` e lido do registro
        # ARMAZENADO (`old`), NUNCA do payload do cliente — assim o cliente nao pode
        # "marcar como efemero" um placement persistente para apaga-lo.
        removed = old.reject { |p| new_ids.include?((p['id'] || p[:id]).to_s) }
        non_ephemeral_removed = removed.reject { |p| p['ephemeral'] || p[:ephemeral] }
        return forbidden if non_ephemeral_removed.any?
      end
    end

    # Full token snapshots are not concurrency-safe: a delayed tab can restore
    # stale positions, equipment and customization for every token. All current
    # clients use #mutate_tokens; rejecting this legacy contract also prevents an
    # already-open old tab from corrupting the session after a deploy.
    if attrs.key?(:tokens)
      return render(
        json: { error: 'Snapshot completo de tokens desativado; recarregue a pagina' },
        status: :conflict,
      )
    end

    if @map.update(attrs)
      apply_background!(@map)
      broadcast_update_diffs
      # Resposta SLIM: o front (flushPatch) DESCARTA o corpo — a verdade chega via
      # `broadcast_update_diffs` (diff realtime) e pelo estado otimista local. Antes
      # reserializávamos o mapa FULL (base64 do fundo + matriz de 40k cells, MBs)
      # a cada PATCH só para o cliente jogar fora. `broadcast_update_diffs` segue
      # mandando o diff necessário aos outros clientes.
      render json: { battle_map: BattleMapSerializer.serialize(@map, mode: :slim) }, status: 200
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

  # PATCH /api/v1/player/battle_maps/:id/thumbnail  { background_thumbnail: <data uri webp> }
  # Persiste a MINIATURA derivada (gerada client-side p/ mapas antigos, no backfill
  # lazy do MapList). Usa update_column: NÃO toca updated_at (não reordena a lista)
  # nem dispara broadcast — é dado derivado do fundo, não uma edição do mapa.
  def thumbnail
    return forbidden unless @map.writable_by?(@current_user)

    thumb = params[:background_thumbnail].to_s
    return head(:unprocessable_entity) if thumb.bytesize > MAX_THUMBNAIL_BYTES

    @map.update_column(:background_thumbnail, thumb.presence)
    head :no_content
  end

  # POST /api/v1/player/battle_maps/:id/duplicate
  # Deep copy. Util para template -> personalizar.
  def duplicate
    return forbidden unless @map.readable_by?(@current_user)
    # `without_tokens=true` → cópia limpa (sem tokens) p/ importar mapa numa sessão.
    include_tokens = !ActiveModel::Type::Boolean.new.cast(params[:without_tokens])
    copy = BattleMap.duplicate_for_user(@map, @current_user, include_tokens: include_tokens)
    render json: { battle_map: BattleMapSerializer.serialize(copy, mode: :full) }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
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
    trace = Realtime::Telemetry.request_context(request)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Realtime::Telemetry.emit(
      stage: 'command_received',
      domain: 'map',
      event_type: 'token_moved',
      command_id: trace[:command_id],
      client_id: trace[:client_id],
      aggregate_type: 'battle_map_token',
      aggregate_id: params[:token_id],
      actor_id: @current_user&.id,
      outcome: 'pending',
    )

    return forbidden unless @map.readable_by?(@current_user)
    token_id = params[:token_id].to_s
    new_x = params[:x].to_i
    new_y = params[:y].to_i

    # O token e relido dentro do row lock. Sem isso, dois clientes podiam ler o
    # mesmo array e o ultimo save reaplicava posicao/equipamento/customizacao
    # antigos do outro. O lock serializa a escrita e a operacao altera apenas x/y.
    @map.with_lock do
      @map.reload
      tokens = Array(@map.tokens).map(&:deep_dup)
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

      tokens[idx] = token.merge('x' => new_x, 'y' => new_y)
      @map.update!(tokens: tokens)
    end

    Realtime::Telemetry.emit(
      stage: 'command_persisted',
      domain: 'map',
      event_type: 'token_moved',
      command_id: trace[:command_id],
      client_id: trace[:client_id],
      aggregate_type: 'battle_map_token',
      aggregate_id: token_id,
      actor_id: @current_user.id,
      duration_ms: elapsed_ms(started_at),
      outcome: 'succeeded',
    )
    event = MapRealtime::Broadcaster.token_moved(
      @map,
      token_id,
      new_x,
      new_y,
      actor: @current_user,
      command_id: trace[:command_id],
      client_id: trace[:client_id],
    )
    # Resposta :tokens (base + tokens, sem cells/fundo/layers): o front reconcilia
    # só `battle_map.tokens`. Antes serializava o mapa FULL (base64 + 40k cells) a
    # CADA arrasto — o 'View ~1268ms' e a transferência de MBs no caminho mais quente.
    render json: {
      battle_map: BattleMapSerializer.serialize(@map, mode: :tokens),
      realtime: {
        commandId: trace[:command_id],
        clientId: trace[:client_id],
        eventId: event[:event_id],
      }.compact,
    }, status: 200
  end

  def launch_projectile
    projectile = BattleMapProjectiles.launch!(map: @map, user: @current_user, params: params)
    # Resposta :slim (base, sem cells/fundo/tokens): o front só consome
    # `response.projectile` — NUNCA `battle_map`. As mudanças (projétil + tokens)
    # chegam a todos via broadcast (dropped_projectiles_changed/tokens_changed).
    # Antes serializávamos o mapa FULL (base64 + 40k cells) a CADA tiro à
    # distância: ~530ms de 'Views' + 180k allocations por disparo, o que sobrou
    # da lentidão do ataque de besta.
    render json: { projectile: projectile, battle_map: BattleMapSerializer.serialize(@map, mode: :slim) }, status: :created
  rescue BattleMapProjectiles::Forbidden => e
    render json: { error: e.message }, status: :forbidden
  rescue BattleMapProjectiles::NotFound => e
    render json: { error: e.message }, status: :not_found
  rescue BattleMapProjectiles::Invalid, ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def resolve_projectile
    projectile = BattleMapProjectiles.resolve!(
      map: @map, user: @current_user,
      projectile_id: params[:projectile_id], roll_group_id: params[:roll_group_id],
      outcome: params[:outcome]
    )
    render json: { projectile: projectile }, status: :ok
  rescue BattleMapProjectiles::Forbidden => e
    render json: { error: e.message }, status: :forbidden
  rescue BattleMapProjectiles::NotFound => e
    render json: { error: e.message }, status: :not_found
  rescue BattleMapProjectiles::Invalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def pick_up_projectile
    item = BattleMapProjectiles.pick_up!(
      map: @map, user: @current_user,
      projectile_id: params[:projectile_id], character_id: params[:character_id],
      token_id: params[:token_id], equip: params[:equip]
    )
    render json: {
      sheet_item: item.as_inventory_json,
      sheet_items: item.sheet.sheet_items.reload.map(&:as_inventory_json)
    }, status: :ok
  rescue BattleMapProjectiles::Forbidden => e
    render json: { error: e.message }, status: :forbidden
  rescue BattleMapProjectiles::NotFound => e
    render json: { error: e.message }, status: :not_found
  rescue BattleMapProjectiles::Invalid, ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def elapsed_ms(started_at)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(2)
  end

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
      :background_image_url, :background_thumbnail,
      :background_image_offset_x, :background_image_offset_y,
      :background_image_pixel_width, :background_image_pixel_height,
      :grid_opacity, :schema_version, :distance_display_unit, :cell_world_ft,
      :fog_mode, :map_kind,
    ).to_h

    # O fundo FULL NÃO é mais gravado na coluna text: quando vem um data URI, ele
    # é decodificado e anexado ao Active Storage em `apply_background!` (após save).
    # Removemos a chave aqui p/ o update/create não regravar o base64 gigante na
    # coluna. (`background_thumbnail` — data URI pequeno — segue como coluna.)
    permitted.delete('background_image_url')

    unsafe = raw.to_unsafe_h.with_indifferent_access
    permitted[:cells]        = unsafe[:cells]        if unsafe.key?(:cells)
    permitted[:tokens]       = unsafe[:tokens]       if unsafe.key?(:tokens)
    permitted[:walls]        = unsafe[:walls]        if unsafe.key?(:walls)
    permitted[:fog]          = unsafe[:fog]          if unsafe.key?(:fog)
    permitted[:measurements]       = unsafe[:measurements]       if unsafe.key?(:measurements)
    permitted[:aoe_placements]     = unsafe[:aoe_placements]     if unsafe.key?(:aoe_placements)
    permitted[:drawings]           = unsafe[:drawings]           if unsafe.key?(:drawings)
    permitted[:player_permissions] = unsafe[:player_permissions] if unsafe.key?(:player_permissions)
    # Fase 2.0 — camadas do Map Builder (nested arrays/objetos; mesmo padrão
    # to_unsafe_h dos demais blobs; shape validado no model).
    permitted[:layers]         = unsafe[:layers]         if unsafe.key?(:layers)
    permitted[:terrain_layers] = unsafe[:terrain_layers] if unsafe.key?(:terrain_layers)
    permitted[:stamps]         = unsafe[:stamps]         if unsafe.key?(:stamps)
    permitted[:paths]          = unsafe[:paths]          if unsafe.key?(:paths)
    permitted[:map_effects]    = unsafe[:map_effects]    if unsafe.key?(:map_effects)
    permitted
  end

  def deep_dup_array(arr)
    BattleMap.deep_dup_nested_arrays(arr)
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
        background_image_pixel_width: legacy_positive_int(h['backgroundImagePixelWidth']),
        background_image_pixel_height: legacy_positive_int(h['backgroundImagePixelHeight']),
        grid_opacity: h['gridOpacity'],
        schema_version: (h['schemaVersion'] || 1).to_i,
        distance_display_unit: %w[ft m].include?(h['distanceDisplayUnit'].to_s) ? h['distanceDisplayUnit'].to_s : 'm',
        cell_world_ft: normalize_legacy_cell_world_ft(h['cellWorldFt']),
        aoe_placements: h['aoePlacements'].is_a?(Array) ? h['aoePlacements'] : [],
        # Fase 2.0 — camadas do builder (opcionais; default vazio mantém
        # mapas legados idênticos).
        layers: h['layers'].is_a?(Array) ? h['layers'] : [],
        terrain_layers: h['terrainLayers'].is_a?(Array) ? h['terrainLayers'] : [],
        stamps: h['stamps'].is_a?(Array) ? h['stamps'] : [],
        paths: h['paths'].is_a?(Array) ? h['paths'] : [],
        map_effects: h['mapEffects'].is_a?(Hash) ? h['mapEffects'] : {},
        map_kind: BattleMap::MAP_KINDS.include?(h['mapKind'].to_s) ? h['mapKind'].to_s : 'battle',
      },
    }
  end

  def legacy_positive_int(raw)
    return nil if raw.nil? || raw == ''
    i = raw.to_i
    i.positive? ? i : nil
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
    # Fase 2.0 — edições do Map Builder (layers/stamps/paths/effects) emitem
    # `map_updated` full por ora (DM-only, debounced). Diffs granulares por
    # camada virão na Fase 2.1 junto do painel de camadas.
    # Troca de fundo via Active Storage (attach) NÃO aparece em previous_changes da
    # coluna → @background_changed (setado em apply_background!) força o broadcast full.
    structural = @background_changed ||
      (changes.keys & %w[name width height cell_size_px background_image_url grid_opacity group_id walls distance_display_unit cell_world_ft fog_mode layers terrain_layers stamps paths map_effects map_kind]).any?

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

  # Fundo → Active Storage: se o param `background_image_url` vier como data URI
  # (base64), decodifica e anexa ao blob (`background_image`), zerando a coluna text
  # legada; se vier VAZIO/nil, remove o fundo; se vier uma URL (eco do próprio
  # endpoint), ignora (mantém o blob atual). Marca @background_changed p/ o broadcast
  # (attach não mexe em previous_changes da coluna).
  def apply_background!(map)
    bm = params[:battle_map]
    return unless bm.respond_to?(:key?) && bm.key?(:background_image_url)

    raw = bm[:background_image_url]
    if raw.is_a?(String) && raw.start_with?('data:')
      decoded = decode_background_data_uri(raw)
      return unless decoded

      bytes, content_type, ext = decoded
      map.background_image.attach(io: StringIO.new(bytes), filename: "bg-#{map.id}.#{ext}", content_type: content_type)
      map.update_column(:background_image_url, nil) if map.background_image_url.present?
      @background_changed = true
    elsif raw.blank?
      map.background_image.purge if map.background_image.attached?
      map.update_column(:background_image_url, nil) if map.background_image_url.present?
      @background_changed = true
    end
    # else: URL (não-data) → não faz nada (o fundo já está no blob).
  rescue StandardError => e
    Rails.logger.warn("[BattleMapsController#apply_background!] #{e.class}: #{e.message}")
  end

  BACKGROUND_DATA_URI_RE = %r{\Adata:image/(png|jpe?g|webp|gif);base64,([A-Za-z0-9+/=\s]+)\z}i.freeze

  # data URI base64 → [bytes, content_type, ext]. Nil se não casar/decodificar.
  def decode_background_data_uri(str)
    m = BACKGROUND_DATA_URI_RE.match(str)
    return nil unless m

    fmt = m[1].downcase
    mime = fmt == 'jpg' ? 'jpeg' : fmt
    ext  = mime == 'jpeg' ? 'jpg' : mime
    bytes = Base64.strict_decode64(m[2].gsub(/\s+/, ''))
    return nil if bytes.blank?

    [bytes, "image/#{mime}", ext]
  rescue ArgumentError
    nil # base64 malformado
  end

  # Valida a assinatura do fundo contra o blob deste mapa (autz do #background).
  # Purpose DEVE bater com BattleMapSerializer::BACKGROUND_SIG_PURPOSE.
  def valid_background_sig?(blob, sig)
    return false if sig.blank?

    verified = Rails.application.message_verifier('battle_map_background').verified(sig)
    verified.to_s == blob.id.to_s
  rescue StandardError
    false
  end
end
