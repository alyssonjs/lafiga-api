# frozen_string_literal: true

# Session feed (chat + dice bubble) over ActionCable, com persistência
# (SessionFeedItem) para histórico entre conexões e dispositivos.
# Subscribe: { channel: 'SessionFeedChannel', schedule_id:, token: }
# Client perform: feed_item with { item: <FeedItem hash> }
#
# Pipeline por mensagem válida:
#   1. Rate limit por user/schedule (SessionFeed::RateLimit).
#   2. Normaliza payload (sanitização + whitelist de campos).
#   3. SessionFeed::Persist.call (idempotente, dedup por client_id, upsert
#      roll_pending → roll, atualização in-place de attack_hit_resolution).
#   4. ActionCable.server.broadcast para os subscribers.
#
# Falhas em (3) bloqueiam eventos duráveis: nenhum cliente deve observar como
# confirmado algo que o servidor não conseguiu persistir. Histórico via REST:
# GET /api/v1/player/schedules/:id/session_feed_items.
class SessionFeedChannel < ApplicationCable::Channel
  # Stickers locais (data URL base64) precisam de folga; ainda rate-limited por utilizador.
  MAX_PAYLOAD_BYTES = 28_672
  MAX_CHAT_TEXT_CHARS = 2_000
  MAX_CHAT_MEDIA_URL_LENGTH = 2_048
  MAX_STICKER_DATA_URL_CHARS = 18_000
  MAX_STICKER_DATA_URL_B64_CHARS = 14_000
  MAX_STICKER_DECODED_BYTES = 12_000
  MAX_ID_LENGTH = 128

  CHAT_ROLES = %w[dm player visitor].freeze
  ROLL_TYPES = %w[attack damage skill save ability initiative heal spell custom].freeze
  ATTACK_HIT_OUTCOMES = %w[pending hit miss].freeze
  DM_ATTACK_OUTCOMES = %w[hit miss].freeze
  # FX efêmero de números de dano flutuantes (floating_fx): relayado a todos, NÃO
  # persistido (fora de SessionFeedItem::KINDS → SessionFeed::Persist ignora).
  FX_KINDS = %w[damage heal].freeze
  MAX_FX_FLOATS = 12
  MAX_FX_DURATION_MS = 6_000
  DEFAULT_FX_DURATION_MS = 1_200
  # Quebra de dano POR TIPO no card (arma + riders elementais): concussão, fogo…
  MAX_DAMAGE_LINES = 16
  DAMAGE_LINE_MULTS = [0, 0.5, 1, 2].freeze
  # Preview de área ao vivo (aoe_preview): formas válidas + teto de tamanho.
  AOE_PREVIEW_SHAPES = %w[sphere cone cube line cylinder].freeze
  MAX_AOE_SIZE_FT = 500
  # Kinds efêmeros de alta frequência (previews de arraste): bucket de rate-limit
  # próprio por-kind + NÃO persistem. Novo preview vivo = adicionar aqui.
  # `spell_fx` = FX animado one-shot de magia de área (não persiste; some no fim do turno).
  EPHEMERAL_PREVIEW_KINDS = %w[aoe_preview oa_threat spell_fx].freeze
  MAX_OA_THREATS = 24
  # FX de magia de área (spell_fx): elementos/formas válidos (espelham SpellEffects).
  SPELL_FX_ELEMENTS = %w[fire cold lightning acid radiant necrotic force thunder poison psychic].freeze
  # `projectile`: NAO e area — e um PROJETIL magico voando do conjurador ate o
  # alvo (Melodia Flamejante), como a flecha/arma de arremesso. Reusa
  # `col/row` (origem) + `direction`/`cells` (destino derivado) do mesmo payload.
  SPELL_FX_SHAPES = %w[circle cone line square projectile].freeze
  MAX_SPELL_FX_CELLS = 200

  def self.stream_name_for(schedule_id)
    "session_feed_#{schedule_id}"
  end

  # Um stream POR CANAL restrito. Quem não é do canal nunca o assina — é isso, e
  # não um filtro no cliente, que mantém a conversa fora do navegador alheio.
  def self.audience_stream_name_for(schedule_id, audience)
    return stream_name_for(schedule_id) if audience.to_s == SessionFeedItem::AUDIENCE_ALL

    "session_feed_#{audience}_#{schedule_id}"
  end

  def subscribed
    token = params[:token].to_s
    @current_user = authenticate_token(token)
    unless @current_user
      trace_realtime(
        stage: 'subscription_rejected', domain: 'feed', outcome: 'rejected',
        aggregate_type: 'schedule', aggregate_id: params[:schedule_id], error_class: 'authentication_failed'
      )
      return reject
    end

    schedule = find_schedule_from_params
    unless schedule
      trace_realtime(
        stage: 'subscription_rejected', domain: 'feed', outcome: 'rejected',
        aggregate_type: 'schedule', aggregate_id: params[:schedule_id], error_class: 'aggregate_not_found'
      )
      return reject
    end
    unless can_read?(schedule, @current_user)
      trace_realtime(
        stage: 'subscription_rejected', domain: 'feed', outcome: 'rejected',
        aggregate_type: 'schedule', aggregate_id: schedule.id, error_class: 'authorization_failed'
      )
      return reject
    end

    @schedule_id = schedule.id
    @audiences = SessionFeed::Audience.readable(schedule, @current_user)
    @audiences.each { |a| stream_from self.class.audience_stream_name_for(@schedule_id, a) }
    trace_realtime(
      stage: 'subscription_confirmed', domain: 'feed', outcome: 'succeeded',
      aggregate_type: 'schedule', aggregate_id: @schedule_id
    )
  end

  def unsubscribed
    trace_realtime(
      stage: 'subscription_removed', domain: 'feed', outcome: 'succeeded',
      aggregate_type: 'schedule', aggregate_id: @schedule_id || params[:schedule_id]
    )
  end

  def feed_item(data)
    return unless @schedule_id && @current_user

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    payload = data.is_a?(Hash) ? data.stringify_keys : {}
    item = payload['item']
    item_hash = item.is_a?(Hash) ? item.stringify_keys : {}
    kind = item_hash['kind'].to_s
    trace = feed_trace(item_hash)

    Realtime::Telemetry.emit(
      stage: 'command_received',
      domain: 'feed',
      event_type: kind,
      command_id: trace[:command_id],
      client_id: trace[:client_id],
      connection_id: realtime_connection_id,
      aggregate_type: 'schedule',
      aggregate_id: @schedule_id,
      actor_id: @current_user.id,
      outcome: 'pending',
    )

    # Previews efêmeros (mouse-move / arraste) são de alta frequência → cada kind tem
    # bucket de rate-limit PRÓPRIO e generoso, separado do chat/rolls (bucket default).
    ephemeral = EPHEMERAL_PREVIEW_KINDS.include?(kind)
    rate_ok =
      if ephemeral
        SessionFeed::RateLimit.allow?(@current_user.id, @schedule_id, bucket: kind, limit: SessionFeed::RateLimit::AOE_PREVIEW_LIMIT)
      else
        SessionFeed::RateLimit.allow?(@current_user.id, @schedule_id)
      end
    unless rate_ok
      trace_feed_rejection(kind, trace, 'rate_limited', started_at)
      Rails.logger.warn(
        {
          event: 'session_feed.throttled',
          user_id: @current_user.id,
          schedule_id: @schedule_id,
          bucket: ephemeral ? kind : 'default',
        }.to_json,
      )
      return
    end

    normalized = normalize_item(item)
    if normalized.blank?
      trace_feed_rejection(kind, trace, 'invalid_payload', started_at)
      return
    end

    # Canal do item, resolvido UMA vez para todos os kinds: o caderno do Mestre
    # guarda ROLAGENS, não só texto. Valor desconhecido cai em `all` — o padrão
    # seguro é o visível; nunca inventar privacidade a partir de lixo do cliente.
    normalized['audience'] =
      item_hash['audience'].to_s.presence_in(SessionFeedItem::AUDIENCES) ||
      SessionFeedItem::AUDIENCE_ALL

    event_id = SecureRandom.uuid
    normalized['clientId'] = trace[:client_id] if trace[:client_id]
    normalized['commandId'] = trace[:command_id] if trace[:command_id]
    normalized['eventId'] = event_id

    # A confirmação V/X é uma decisão do Mestre. Além de impedir que outro
    # participante falsifique o resultado, resolver o projétil aqui garante o
    # voo e a queda mesmo se a aba que exibe o card perder o callback REST. Isso
    # vale para acerto e erro e independe do estado local do atacante. O serviço
    # é idempotente, portanto o REST do cliente pode repetir.
    # Escrever num canal restrito exige poder lê-lo. Sem esta guarda, uma aba do
    # Mestre postaria no combinado da equipe — e um jogador, no caderno secreto.
    item_audience = normalized['audience'].presence || SessionFeedItem::AUDIENCE_ALL
    unless Array(@audiences).include?(item_audience)
      trace_feed_rejection(kind, trace, 'authorization_failed', started_at)
      return
    end

    if normalized['kind'] == 'attack_hit_resolution'
      unless Group.user_is_dm?(@current_user)
        trace_feed_rejection(kind, trace, 'authorization_failed', started_at)
        return
      end
      unless resolve_attack_projectile(normalized)
        trace_feed_rejection(kind, trace, 'projectile_resolution_failed', started_at)
        return
      end
    end

    if normalized.to_json.bytesize > MAX_PAYLOAD_BYTES
      trace_feed_rejection(kind, trace, 'payload_too_large', started_at)
      Rails.logger.warn({ event: 'session_feed.rejected_oversize', schedule_id: @schedule_id }.to_json)
      return
    end

    # Só os kinds duráveis entram no histórico. Eventos de coordenação válidos,
    # como save_prompt_resolved e damage_mitigation, são broadcast-only; tratá-los
    # como falha de persistência criaria falsos positivos na telemetria.
    if SessionFeedItem::KINDS.include?(normalized['kind'])
      persisted_item = persist_item(normalized)
      persisted = persisted_item.present?
      Realtime::Telemetry.emit(
        stage: persisted ? 'command_persisted' : 'command_failed',
        domain: 'feed',
        event_type: normalized['kind'],
        event_id: event_id,
        command_id: trace[:command_id],
        client_id: trace[:client_id],
        connection_id: realtime_connection_id,
        aggregate_type: 'schedule',
        aggregate_id: @schedule_id,
        actor_id: @current_user.id,
        duration_ms: elapsed_ms(started_at),
        outcome: persisted ? 'succeeded' : 'failed',
        error_class: persisted ? nil : 'persistence_failed',
      )
      unless persisted
        trace_feed_rejection(kind, trace, 'persistence_failed', started_at)
        return
      end

      # Para confirmações persistidas, o resultado gravado é a autoridade. Uma
      # segunda aba que tente inverter a primeira decisão não pode emitir um eco
      # contraditório. Rolls órfãos ainda degradam para broadcast efêmero.
      if normalized['kind'] == 'attack_hit_resolution' && persisted_item.present? &&
         persisted_item.payload['attackHitOutcome'].to_s != normalized['outcome'].to_s
        trace_feed_rejection(kind, trace, 'attack_outcome_conflict', started_at)
        return
      end

      # Chat/roll/pending usam o payload first-write-wins persistido. Um retry
      # concorrente com o mesmo id jamais pode transmitir outro total/texto.
      normalized = persisted_item.payload unless normalized['kind'] == 'attack_hit_resolution'
    end

    ActionCable.server.broadcast(
      self.class.audience_stream_name_for(@schedule_id, item_audience),
      normalized,
    )
    Realtime::Telemetry.emit(
      stage: 'event_broadcast',
      domain: 'feed',
      event_type: normalized['kind'],
      event_id: normalized['eventId'] || event_id,
      command_id: trace[:command_id],
      client_id: trace[:client_id],
      connection_id: realtime_connection_id,
      aggregate_type: 'schedule',
      aggregate_id: @schedule_id,
      actor_id: @current_user.id,
      duration_ms: elapsed_ms(started_at),
      outcome: 'succeeded',
    )
  end

  private

  # Persiste o item já normalizado. Retorna o registro para decisões que precisam
  # reconciliar o valor autoritativo antes do broadcast.
  def persist_item(normalized)
    SessionFeed::Persist.call(schedule_id: @schedule_id, normalized: normalized)
  rescue StandardError => e
    Rails.logger.warn(
      { event: 'session_feed.persist_failed',
        schedule_id: @schedule_id,
        error: e.class.name,
        message: e.message }.to_json,
    )
    nil
  end

  def feed_trace(item)
    {
      command_id: Realtime::Telemetry.identifier(item['commandId']) ||
        Realtime::Telemetry.identifier(item['rollGroupId']) ||
        Realtime::Telemetry.identifier(item['id']),
      client_id: Realtime::Telemetry.identifier(item['clientId']) || realtime_client_id,
    }
  end

  def trace_feed_rejection(kind, trace, error_class, started_at)
    Realtime::Telemetry.emit(
      stage: 'command_rejected',
      domain: 'feed',
      event_type: kind,
      command_id: trace[:command_id],
      client_id: trace[:client_id],
      connection_id: realtime_connection_id,
      aggregate_type: 'schedule',
      aggregate_id: @schedule_id,
      actor_id: @current_user.id,
      duration_ms: elapsed_ms(started_at),
      outcome: 'rejected',
      error_class: error_class,
    )
  end

  def elapsed_ms(started_at)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(2)
  end

  # Aceita id numérico ou prefixo UI `api-123` (mesmo contrato que scheduleAdapters no front).
  def find_schedule_from_params
    raw = params[:schedule_id]
    sid =
      if raw.is_a?(String) && raw.match?(/\Aapi-\d+\z/i)
        raw.sub(/\Aapi-/i, '')
      else
        raw
      end
    Schedule.find_by(id: sid)
  end

  def authenticate_token(token)
    return nil if token.blank?
    return nil if ValidateJwtToken.where(token: token).exists?

    payload = JsonWebToken.decode(token)
    uid = payload[:user_id] || payload[:id]
    User.find_by(id: uid)
  rescue ExceptionHandler::InvalidToken, JWT::DecodeError, StandardError
    nil
  end

  # Same hub rule as SessionRealtimeChannel (any authenticated user).
  def can_read?(_schedule, user)
    user.present?
  end

  def sanitize_hex_color(raw)
    s = raw.to_s.strip
    return nil if s.blank?
    return s if s.match?(/\A#[0-9a-f]{3}\z/i) || s.match?(/\A#[0-9a-f]{6}\z/i)

    nil
  end

  def normalize_item(item)
    return nil unless item.is_a?(Hash)

    h = item.stringify_keys
    kind = h['kind']
    case kind
    when 'chat'
      normalize_chat(h)
    when 'roll'
      normalize_roll(h)
    when 'roll_pending'
      normalize_roll_pending(h)
    when 'attack_hit_resolution'
      normalize_attack_hit_resolution(h)
    when 'save_prompt_resolved'
      normalize_save_prompt_resolved(h)
    when 'aoe_preview'
      normalize_aoe_preview(h)
    when 'oa_threat'
      normalize_oa_threat(h)
    when 'spell_fx'
      normalize_spell_fx(h)
    when 'floating_fx'
      normalize_floating_fx(h)
    when 'damage_mitigation'
      normalize_damage_mitigation(h)
    when 'roll_total_adjusted'
      normalize_roll_total_adjusted(h)
    when 'target_ac_adjusted'
      normalize_target_ac_adjusted(h)
    else
      nil
    end
  end

  def normalize_chat(h)
    text = h['text'].to_s.strip
    gif_url = sanitize_chat_media_url(h['gifUrl'])
    sticker_url = sanitize_sticker_ref(h['stickerUrl'])
    return nil if text.empty? && gif_url.blank? && sticker_url.blank?
    return nil if text.length > MAX_CHAT_TEXT_CHARS

    role = h['senderRole'].to_s
    return nil unless CHAT_ROLES.include?(role)

    id = h['id'].to_s
    return nil if id.empty? || id.length > MAX_ID_LENGTH

    ts = h['timestamp']
    return nil unless ts.is_a?(Numeric) || ts.to_s.match?(/\A\d+\z/)

    out = {
      'kind' => 'chat',
      'id' => id,
      'timestamp' => ts.is_a?(Numeric) ? ts : ts.to_i,
      'sessionId' => @schedule_id.to_s,
      'senderName' => h['senderName'].to_s.truncate(120),
      'senderRole' => role,
      'text' => text.truncate(MAX_CHAT_TEXT_CHARS),
    }
    cn = h['characterName']
    out['characterName'] = cn.to_s.truncate(120) if cn.present?
    if gif_url.present?
      out['gifUrl'] = gif_url
    elsif sticker_url.present?
      out['stickerUrl'] = sticker_url
    end
    accent = sanitize_hex_color(h['cardAccentColor'])
    out['cardAccentColor'] = accent if accent.present?
    out
  end

  def sanitize_chat_media_url(raw)
    u = raw.to_s.strip
    return nil if u.blank?
    return nil if u.length > MAX_CHAT_MEDIA_URL_LENGTH
    return nil unless u.match?(/\Ahttps:\/\//i)

    uri = URI.parse(u)
    return nil unless uri.is_a?(URI::HTTPS) && uri.host.present?

    u.truncate(MAX_CHAT_MEDIA_URL_LENGTH)
  rescue URI::InvalidURIError
    nil
  end

  # HTTPS (Twemoji, CDN) ou data:image/*;base64,... (sticker comprimido no cliente).
  def sanitize_sticker_ref(raw)
    u = sanitize_chat_media_url(raw)
    return u if u.present?

    sanitize_sticker_data_url(raw)
  end

  def sanitize_sticker_data_url(raw)
    s = raw.to_s.strip
    return nil if s.blank?
    return nil if s.length > MAX_STICKER_DATA_URL_CHARS
    return nil unless s.start_with?('data:image/')

    m = s.match(/\Adata:image\/(png|jpeg|jpg|webp|gif);base64,([A-Za-z0-9+\/=\r\n]+)\z/i)
    return nil unless m

    mime = m[1].downcase
    mime = 'jpeg' if mime == 'jpg'
    b64 = m[2].gsub(/\s+/, '')
    return nil if b64.length > MAX_STICKER_DATA_URL_B64_CHARS
    return nil unless b64.match?(/\A[A-Za-z0-9+\/]*=*\z/)

    decoded = Base64.strict_decode64(b64)
    return nil if decoded.bytesize > MAX_STICKER_DECODED_BYTES
    return nil if decoded.bytesize < 8

    return nil unless sticker_magic_matches?(decoded, mime)

    "data:image/#{mime};base64,#{b64}"
  rescue ArgumentError
    nil
  end

  def sticker_magic_matches?(bin, mime)
    case mime
    when 'png'
      bin.start_with?("\x89PNG\r\n\x1a\n".b)
    when 'jpeg'
      bin.start_with?("\xff\xd8\xff".b)
    when 'gif'
      bin.start_with?('GIF8'.b)
    when 'webp'
      bin.bytesize >= 12 && bin[0..3] == 'RIFF'.b && bin[8..11] == 'WEBP'.b
    else
      false
    end
  end

  def normalize_roll(h)
    SessionFeed::RollNormalizer.call(schedule_id: @schedule_id, item: h)
  end

  # Sanitiza a quebra de dano POR TIPO ({type, raw, final, mult}[]) — usada tanto
  # na rolagem de dano (damageLines) quanto na resolução da mitigação (lines).
  # Descarta linhas malformadas; cap em MAX_DAMAGE_LINES; mult restrito a
  # {0, 0.5, 1, 2}. Retorna nil quando nada válido resta.
  def sanitize_damage_lines(raw)
    return nil unless raw.is_a?(Array)

    lines = raw.first(MAX_DAMAGE_LINES).filter_map do |ln|
      next nil unless ln.is_a?(Hash)

      l = ln.stringify_keys
      type = l['type'].to_s.slice(0, 24)
      next nil if type.empty?

      raw_i = l['raw'].is_a?(Numeric) ? l['raw'].to_i : Integer(l['raw'], exception: false)
      final_i = l['final'].is_a?(Numeric) ? l['final'].to_i : Integer(l['final'], exception: false)
      next nil if raw_i.nil? || final_i.nil? || raw_i.negative? || final_i.negative?

      mult_f = l['mult'].is_a?(Numeric) ? l['mult'].to_f : Float(l['mult'], exception: false)
      mult_f = 1.0 unless DAMAGE_LINE_MULTS.include?(mult_f)

      { 'type' => type, 'raw' => raw_i, 'final' => final_i, 'mult' => mult_f }
    end

    lines.presence
  end

  # Atualiza um card de dano já emitido com o valor REAL pós-mitigação + a quebra
  # por tipo (cross-device). Efêmero: relayado a todos, não persistido (fora de
  # SessionFeedItem::KINDS). Casa por `rollGroupId` no cliente.
  def normalize_damage_mitigation(h)
    id = h['id'].to_s
    return nil if id.empty? || id.length > MAX_ID_LENGTH

    ts = h['timestamp']
    return nil unless ts.is_a?(Numeric) || ts.to_s.match?(/\A\d+\z/)

    rg = h['rollGroupId'].to_s
    return nil if rg.empty? || rg.length > MAX_ID_LENGTH

    mt = h['mitigatedTotal']
    mt_i = mt.is_a?(Numeric) ? mt.to_i : Integer(mt, exception: false)
    return nil if mt_i.nil?

    out = {
      'kind' => 'damage_mitigation',
      'id' => id,
      'timestamp' => ts.is_a?(Numeric) ? ts : ts.to_i,
      'sessionId' => @schedule_id.to_s,
      'rollGroupId' => rg,
      'mitigatedTotal' => mt_i,
      'tag' => h['tag'].to_s.slice(0, 24),
    }
    lines = sanitize_damage_lines(h['lines'])
    out['lines'] = lines if lines.present?
    out
  end

  # Atualização in-place do TOTAL de uma rolagem já postada (eco p/ todos os
  # clientes). Nasceu para a Inspiração Bárdica: o portador do dado decide somá-lo
  # DEPOIS de ver o d20, então o card precisa passar a mostrar o total final.
  # Mesmo formato do `damage_mitigation`, mas para o total de qualquer rolagem.
  def normalize_roll_total_adjusted(h)
    id = h['id'].to_s
    return nil if id.empty? || id.length > MAX_ID_LENGTH

    ts = h['timestamp']
    return nil unless ts.is_a?(Numeric) || ts.to_s.match?(/\A\d+\z/)

    rg = h['rollGroupId'].to_s
    return nil if rg.empty? || rg.length > MAX_ID_LENGTH

    at = h['adjustedTotal']
    at_i = at.is_a?(Numeric) ? at.to_i : Integer(at, exception: false)
    return nil if at_i.nil?

    out = {
      'kind' => 'roll_total_adjusted',
      'id' => id,
      'timestamp' => ts.is_a?(Numeric) ? ts : ts.to_i,
      'sessionId' => @schedule_id.to_s,
      'rollGroupId' => rg,
      'adjustedTotal' => at_i,
      'tag' => h['tag'].to_s.slice(0, 32),
    }
    breakdown = h['adjustedBreakdown'].to_s
    out['adjustedBreakdown'] = breakdown.slice(0, 300) if breakdown.present?
    # SOBREPOSIÇÃO deliberada (reações que se compõem na mesma rolagem): sem
    # passar pelo canal, o cliente remoto ficava no primeiro-vence e mostrava
    # só o primeiro ajuste (regra da mesa 18/08: ajustes se sobrepõem).
    out['replace'] = true if h['replace'] == true
    # d20 SUBSTITUTO da rerrolagem — sinal explícito para o holder do TR seguro
    # (antes ele deduzia invertendo o total, e a penalidade publicada na hora
    # entrava nessa conta como se fosse dado novo).
    rd = h['rerolledD20']
    rd_i = rd.is_a?(Numeric) ? rd.to_i : Integer(rd, exception: false)
    out['rerolledD20'] = rd_i if rd_i&.between?(1, 20)
    # Ajuste PARCIAL de uma reação: revisa o card mas NÃO encerra a decisão —
    # outras reações ainda entram no mesmo teste. Sem relay, o cliente remoto
    # fecharia a janela do Bardo seguinte (travou 90 s no playtest de 18/08).
    out['keepsWindowOpen'] = true if h['keepsWindowOpen'] == true
    # Quebra por tipo REVISADA. Quando o ajuste SOMA dano (top-up da Inspiracao
    # em Combate / dado da Melodia Flamejante), o total muda e os chips por tipo
    # tambem precisam mudar — senao o card mostra "21" com o chip "FOGO 11".
    # ⚠️ Campo novo no payload = linha AQUI + caso no spec, no mesmo commit: a
    # whitelist do feed e POR CAMPO, e o que nao esta nela morre no canal.
    lines = sanitize_damage_lines(h['lines'])
    out['lines'] = lines if lines.present?
    out
  end

  # Irmão do `roll_total_adjusted`: revisa a CA DO ALVO num card de ataque já
  # postado. A Inspiração em Combate (Bardo, Colégio da Bravura) deixa o alvo
  # somar um dado à CA contra AQUELE ataque, e o V/X do Mestre é julgado contra
  # ela — sem o eco, só o cliente que resolveu veria a CA nova.
  def normalize_target_ac_adjusted(h)
    id = h['id'].to_s
    return nil if id.empty? || id.length > MAX_ID_LENGTH

    ts = h['timestamp']
    return nil unless ts.is_a?(Numeric) || ts.to_s.match?(/\A\d+\z/)

    rg = h['rollGroupId'].to_s
    return nil if rg.empty? || rg.length > MAX_ID_LENGTH

    ac = h['adjustedTargetAc']
    ac_i = ac.is_a?(Numeric) ? ac.to_i : Integer(ac, exception: false)
    return nil if ac_i.nil?

    {
      'kind' => 'target_ac_adjusted',
      'id' => id,
      'timestamp' => ts.is_a?(Numeric) ? ts : ts.to_i,
      'sessionId' => @schedule_id.to_s,
      'rollGroupId' => rg,
      'adjustedTargetAc' => ac_i,
      'tag' => h['tag'].to_s.slice(0, 48),
    }
  end

  # Atualização in-place do `attackHitOutcome` numa rolagem de ataque (eco p/ todos os clientes).
  def normalize_attack_hit_resolution(h)
    return nil unless h.is_a?(Hash)

    h = h.stringify_keys
    return nil unless h['kind'].to_s == 'attack_hit_resolution'

    id = h['id'].to_s
    return nil if id.empty? || id.length > MAX_ID_LENGTH

    ts = h['timestamp']
    return nil unless ts.is_a?(Numeric) || ts.to_s.match?(/\A\d+\z/)

    roll_group_id = h['rollGroupId'].to_s
    return nil if roll_group_id.empty? || roll_group_id.length > MAX_ID_LENGTH

    outcome = h['outcome'].to_s
    return nil unless DM_ATTACK_OUTCOMES.include?(outcome)

    result = {
      'kind' => 'attack_hit_resolution',
      'id' => id,
      'timestamp' => ts.is_a?(Numeric) ? ts : ts.to_i,
      'sessionId' => @schedule_id.to_s,
      'rollGroupId' => roll_group_id.truncate(MAX_ID_LENGTH),
      'outcome' => outcome
    }

    # Só no ERRO: token que esquivou (+ atacante do lunge) → FX nos clientes. Whitelist.
    if outcome == 'miss'
      dodge = h['dodgeTargetTokenId'].to_s
      result['dodgeTargetTokenId'] = dodge if dodge.present? && dodge.length <= MAX_ID_LENGTH
      atk = h['dodgeAttackerTokenId'].to_s
      result['dodgeAttackerTokenId'] = atk if atk.present? && atk.length <= MAX_ID_LENGTH
    end

    projectile_id = h['projectileId'].to_s
    result['projectileId'] = projectile_id if projectile_id.present? && projectile_id.length <= MAX_ID_LENGTH

    result
  end

  def resolve_attack_projectile(resolution)
    schedule = Schedule.includes(:battle_map).find_by(id: @schedule_id)
    map = schedule&.battle_map
    return true unless map

    # Marca a mesa na instancia: o projetil resolve na camada desta sessao e o
    # evento sai no canal dela. Sem isto, uma mesa resolveria o projetil da outra.
    map.session_scope_schedule_id = schedule.id

    has_projectile = resolution['projectileId'].present? || Array(map.dropped_projectiles).any? do |projectile|
      projectile['rollGroupId'].to_s == resolution['rollGroupId'].to_s
    end
    return true unless has_projectile

    BattleMapProjectiles.resolve!(
      map: map,
      user: @current_user,
      projectile_id: resolution['projectileId'],
      roll_group_id: resolution['rollGroupId'],
      outcome: resolution['outcome'],
    )
    true
  rescue BattleMapProjectiles::NotFound
    # Ataques corpo a corpo tambem possuem rollGroupId e naturalmente nao têm
    # projetil. Nao e erro de transporte nem deve bloquear o V/X no feed.
    true
  rescue BattleMapProjectiles::Error, ActiveRecord::RecordInvalid => e
    Rails.logger.warn(
      {
        event: 'session_feed.projectile_resolution_failed',
        schedule_id: @schedule_id,
        roll_group_id: resolution['rollGroupId'],
        projectile_id: resolution['projectileId'],
        error: e.class.name,
        message: e.message,
      }.to_json,
    )
    false
  end

  # Resolução de PROMPT de TR: quando o dono do alvo (ou o Mestre) rola/dispensa o
  # Teste de Resistência, o botão "Rolar TR" precisa sumir em TODOS os clientes — o
  # card é broadcast, mas a resolução era local (outro cliente ficava com o botão
  # ativo). Igual ao attack_hit_resolution: relayado por rollGroupId, efêmero (não
  # persistido — kind fora de SessionFeedItem::KINDS), atualização in-place.
  def normalize_save_prompt_resolved(h)
    return nil unless h.is_a?(Hash)

    h = h.stringify_keys
    return nil unless h['kind'].to_s == 'save_prompt_resolved'

    id = h['id'].to_s
    return nil if id.empty? || id.length > MAX_ID_LENGTH

    ts = h['timestamp']
    return nil unless ts.is_a?(Numeric) || ts.to_s.match?(/\A\d+\z/)

    roll_group_id = h['rollGroupId'].to_s
    return nil if roll_group_id.empty? || roll_group_id.length > MAX_ID_LENGTH

    {
      'kind' => 'save_prompt_resolved',
      'id' => id,
      'timestamp' => ts.is_a?(Numeric) ? ts : ts.to_i,
      'sessionId' => @schedule_id.to_s,
      'rollGroupId' => roll_group_id.truncate(MAX_ID_LENGTH)
    }
  end

  # Preview AO VIVO de área (aoe_preview): o conjurador transmite a origem/direção
  # resolvidas enquanto move o mouse; os OUTROS clientes recomputam as células e
  # desenham um fantasma. Efêmero (não persiste), relayado, com `sender_id`
  # AUTORITATIVO (do @current_user) p/ o front pular o próprio eco. `phase:'end'`
  # limpa o fantasma. Envia origem+direção (não as células cruas) p/ payload enxuto.
  def normalize_aoe_preview(h)
    return nil unless h.is_a?(Hash)

    h = h.stringify_keys
    return nil unless h['kind'].to_s == 'aoe_preview'

    id = h['id'].to_s
    return nil if id.empty? || id.length > MAX_ID_LENGTH

    ts = h['timestamp']
    return nil unless ts.is_a?(Numeric) || ts.to_s.match?(/\A\d+\z/)

    caster_id = h['casterId'].to_s
    return nil if caster_id.empty? || caster_id.length > MAX_ID_LENGTH

    phase = h['phase'].to_s
    phase = 'move' unless %w[move end].include?(phase)

    out = {
      'kind' => 'aoe_preview',
      'id' => id,
      'timestamp' => ts.is_a?(Numeric) ? ts : ts.to_i,
      'sessionId' => @schedule_id.to_s,
      'senderId' => @current_user.id.to_s,
      'casterId' => caster_id.truncate(MAX_ID_LENGTH),
      'phase' => phase
    }
    # Nonce por ABA (client-provided) — o front usa p/ echo-skip por CLIENTE (2 abas
    # do mesmo user diferem). Não-autoritativo; só afeta a própria visão do emissor.
    client_id = h['clientId'].to_s
    out['clientId'] = client_id.truncate(MAX_ID_LENGTH) if client_id.present?
    return out if phase == 'end' # 'end' só precisa do casterId p/ limpar o fantasma

    shape = h['shape'].to_s
    return nil unless AOE_PREVIEW_SHAPES.include?(shape)

    size_ft = h['sizeFt'].to_f
    return nil unless size_ft.positive? && size_ft <= MAX_AOE_SIZE_FT

    out['shape'] = shape
    out['sizeFt'] = size_ft
    out['originCol'] = h['originCol'].to_i
    out['originRow'] = h['originRow'].to_i
    out['dirCol'] = h['dirCol'].to_i
    out['dirRow'] = h['dirRow'].to_i
    color = sanitize_hex_color(h['color'])
    out['color'] = color if color
    spell_name = h['spellName'].to_s
    out['spellName'] = spell_name.truncate(80) if spell_name.present?
    out
  end

  # Setas de AMEAÇA de Ataque de Oportunidade AO VIVO (oa_threat): enquanto um cliente
  # ARRASTA um token em combate, transmite a célula viva do arraste + os ids dos inimigos
  # que ameaçam (JÁ computados no emissor — a ameaça é definida na origem congelada, então
  # NÃO recomputar no receptor). Efêmero, não persiste. clientId (por aba) p/ echo-skip.
  # `phase:'end'` (soltou/cancelou) limpa as setas.
  # FX animado de magia de área (one-shot). Valida elemento/forma + geometria; a
  # bounding box (bounds) ancora círculo/quadrado sobre a hachura no receptor.
  def normalize_spell_fx(h)
    return nil unless h.is_a?(Hash)

    h = h.stringify_keys
    return nil unless h['kind'].to_s == 'spell_fx'

    id = h['id'].to_s
    return nil if id.empty? || id.length > MAX_ID_LENGTH

    ts = h['timestamp']
    return nil unless ts.is_a?(Numeric) || ts.to_s.match?(/\A\d+\z/)

    element = h['element'].to_s
    return nil unless SPELL_FX_ELEMENTS.include?(element)

    shape = h['shape'].to_s
    return nil unless SPELL_FX_SHAPES.include?(shape)

    cells = h['cells'].to_f
    return nil unless cells.positive? && cells <= MAX_SPELL_FX_CELLS

    out = {
      'kind' => 'spell_fx',
      'id' => id,
      'timestamp' => ts.is_a?(Numeric) ? ts : ts.to_i,
      'sessionId' => @schedule_id.to_s,
      'senderId' => @current_user.id.to_s,
      'element' => element,
      'shape' => shape,
      'col' => h['col'].to_i,
      'row' => h['row'].to_i,
      'cells' => cells,
      'direction' => h['direction'].to_f
    }
    b = h['bounds']
    if b.is_a?(Hash)
      b = b.stringify_keys
      out['bounds'] = {
        'minCol' => b['minCol'].to_i, 'minRow' => b['minRow'].to_i,
        'maxCol' => b['maxCol'].to_i, 'maxRow' => b['maxRow'].to_i
      }
    end
    # Id da magia/cancao que originou o FX. Cada cliente resolve o PERFIL visual
    # (cor/ritmo/forma) pelo catalogo local, entao raio novo NAO faz o payload
    # crescer. ⚠️ Campo novo = linha aqui + caso no spec, no mesmo commit: a
    # whitelist do feed e POR CAMPO e o que nao esta nela morre no canal.
    spell_id = h['spellId'].to_s
    out['spellId'] = spell_id.truncate(MAX_ID_LENGTH) if spell_id.present?
    client_id = h['clientId'].to_s
    out['clientId'] = client_id.truncate(MAX_ID_LENGTH) if client_id.present?
    out
  end

  def normalize_oa_threat(h)
    return nil unless h.is_a?(Hash)

    h = h.stringify_keys
    return nil unless h['kind'].to_s == 'oa_threat'

    id = h['id'].to_s
    return nil if id.empty? || id.length > MAX_ID_LENGTH

    ts = h['timestamp']
    return nil unless ts.is_a?(Numeric) || ts.to_s.match?(/\A\d+\z/)

    dragged_id = h['draggedTokenId'].to_s
    return nil if dragged_id.empty? || dragged_id.length > MAX_ID_LENGTH

    phase = h['phase'].to_s
    phase = 'move' unless %w[move end].include?(phase)

    out = {
      'kind' => 'oa_threat',
      'id' => id,
      'timestamp' => ts.is_a?(Numeric) ? ts : ts.to_i,
      'sessionId' => @schedule_id.to_s,
      'senderId' => @current_user.id.to_s,
      'draggedTokenId' => dragged_id.truncate(MAX_ID_LENGTH),
      'phase' => phase
    }
    client_id = h['clientId'].to_s
    out['clientId'] = client_id.truncate(MAX_ID_LENGTH) if client_id.present?
    return out if phase == 'end' # 'end' só precisa do draggedTokenId p/ limpar

    out['dragCol'] = h['dragCol'].to_i
    out['dragRow'] = h['dragRow'].to_i
    # Distância que o token vai percorrer (exibida no fantasma remoto). Opcional.
    dist = h['dragDistanceFt']
    out['dragDistanceFt'] = dist.to_f if dist.is_a?(Numeric) || dist.to_s.match?(/\A-?\d+(\.\d+)?\z/)
    threat_ids = h['threatTokenIds']
    threat_ids = [] unless threat_ids.is_a?(Array)
    out['threatTokenIds'] = threat_ids
                            .first(MAX_OA_THREATS)
                            .map { |t| t.to_s }
                            .reject { |t| t.empty? || t.length > MAX_ID_LENGTH }
    out
  end

  # FX efêmero: números de dano flutuantes sobre um token. Relayado a todos os
  # subscribers, mas NÃO persistido (kind fora de SessionFeedItem::KINDS). Cada
  # `floats[i]` = { type (string curta), value (int) }.
  def normalize_floating_fx(h)
    id = h['id'].to_s
    return nil if id.empty? || id.length > MAX_ID_LENGTH

    ts = h['timestamp']
    return nil unless ts.is_a?(Numeric) || ts.to_s.match?(/\A\d+\z/)

    token_id = h['tokenId'].to_s
    return nil if token_id.empty? || token_id.length > MAX_ID_LENGTH

    raw_floats = h['floats']
    return nil unless raw_floats.is_a?(Array)

    floats = raw_floats.first(MAX_FX_FLOATS).filter_map do |f|
      next nil unless f.is_a?(Hash)

      fh = f.stringify_keys
      value = fh['value']
      value_i = value.is_a?(Numeric) ? value.to_i : Integer(value, exception: false)
      next nil if value_i.nil?

      { 'type' => fh['type'].to_s.slice(0, 24), 'value' => value_i }
    end
    return nil if floats.empty?

    fx_kind = h['fxKind'].to_s
    fx_kind = 'damage' unless FX_KINDS.include?(fx_kind)

    dur = h['durationMs']
    dur_i = dur.is_a?(Numeric) ? dur.to_i : DEFAULT_FX_DURATION_MS
    dur_i = DEFAULT_FX_DURATION_MS if dur_i <= 0 || dur_i > MAX_FX_DURATION_MS

    normalized = {
      'kind' => 'floating_fx',
      'id' => id,
      'timestamp' => ts.is_a?(Numeric) ? ts : ts.to_i,
      'sessionId' => @schedule_id.to_s,
      'tokenId' => token_id.slice(0, MAX_ID_LENGTH),
      'floats' => floats,
      'fxKind' => fx_kind,
      'durationMs' => dur_i,
    }

    # FX de ataque melee OPCIONAL (atacante avança + alvo treme). Só um par de
    # tokenIds; efêmero como o resto do floating_fx. Whitelist explícito.
    afx = h['attackFx']
    if afx.is_a?(Hash)
      afh = afx.stringify_keys
      atk = afh['attackerTokenId'].to_s
      tgt = afh['targetTokenId'].to_s
      if atk.present? && atk.length <= MAX_ID_LENGTH && tgt.present? && tgt.length <= MAX_ID_LENGTH
        normalized['attackFx'] = { 'attackerTokenId' => atk, 'targetTokenId' => tgt }
      end
    end

    normalized
  end

  # Fase suspense — sem total/d20; o cliente mostra animação até o `roll` com o mesmo rollGroupId.
  def normalize_roll_pending(h)
    type = h['type'].to_s
    return nil unless ROLL_TYPES.include?(type)

    roll_group_id = h['rollGroupId'].to_s
    return nil if roll_group_id.empty? || roll_group_id.length > MAX_ID_LENGTH

    id = h['id'].to_s
    return nil if id.empty? || id.length > MAX_ID_LENGTH

    ts = h['timestamp']
    return nil unless ts.is_a?(Numeric) || ts.to_s.match?(/\A\d+\z/)

    label = h['label'].to_s
    return nil if label.empty? || label.length > 500

    out = {
      'kind' => 'roll_pending',
      'id' => id,
      'rollGroupId' => roll_group_id.truncate(MAX_ID_LENGTH),
      'timestamp' => ts.is_a?(Numeric) ? ts : ts.to_i,
      'sessionId' => @schedule_id.to_s,
      'playerName' => h['playerName'].to_s.truncate(120),
      'characterName' => h['characterName'].to_s.truncate(120),
      'type' => type,
      'label' => label.truncate(500),
    }

    adv = h['advantage'].to_s
    out['advantage'] = adv if %w[normal advantage disadvantage].include?(adv)

    sr = h['senderRole'].to_s
    out['senderRole'] = sr if CHAT_ROLES.include?(sr)
    accent = sanitize_hex_color(h['cardAccentColor'])
    out['cardAccentColor'] = accent if accent.present?

    out
  end
end
