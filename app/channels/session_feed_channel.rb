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
# Falhas em (3) NÃO bloqueiam o broadcast (degrada para comportamento
# anterior — efêmero) mas são logadas. Histórico via REST:
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

  def self.stream_name_for(schedule_id)
    "session_feed_#{schedule_id}"
  end

  def subscribed
    token = params[:token].to_s
    @current_user = authenticate_token(token)
    return reject unless @current_user

    schedule = find_schedule_from_params
    return reject unless schedule
    return reject unless can_read?(schedule, @current_user)

    @schedule_id = schedule.id
    stream_from self.class.stream_name_for(@schedule_id)
  end

  def feed_item(data)
    return unless @schedule_id && @current_user

    unless SessionFeed::RateLimit.allow?(@current_user.id, @schedule_id)
      Rails.logger.warn(
        {
          event: 'session_feed.throttled',
          user_id: @current_user.id,
          schedule_id: @schedule_id,
        }.to_json,
      )
      return
    end

    payload = data.is_a?(Hash) ? data.stringify_keys : {}
    item = payload['item']
    normalized = normalize_item(item)
    return if normalized.blank?

    if normalized.to_json.bytesize > MAX_PAYLOAD_BYTES
      Rails.logger.warn({ event: 'session_feed.rejected_oversize', schedule_id: @schedule_id }.to_json)
      return
    end

    persist_item(normalized)

    ActionCable.server.broadcast(self.class.stream_name_for(@schedule_id), normalized)
  end

  private

  # Persiste o item já normalizado. Falha aqui não bloqueia o broadcast —
  # histórico fica off-line para esta mensagem mas a sessão continua.
  def persist_item(normalized)
    SessionFeed::Persist.call(schedule_id: @schedule_id, normalized: normalized)
  rescue StandardError => e
    Rails.logger.warn(
      { event: 'session_feed.persist_failed',
        schedule_id: @schedule_id,
        error: e.class.name,
        message: e.message }.to_json,
    )
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
    when 'floating_fx'
      normalize_floating_fx(h)
    when 'damage_mitigation'
      normalize_damage_mitigation(h)
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
    type = h['type'].to_s
    return nil unless ROLL_TYPES.include?(type)

    id = h['id'].to_s
    return nil if id.empty? || id.length > MAX_ID_LENGTH

    ts = h['timestamp']
    return nil unless ts.is_a?(Numeric) || ts.to_s.match?(/\A\d+\z/)

    label = h['label'].to_s
    return nil if label.empty? || label.length > 500

    total = h['total']
    total_i = total.is_a?(Numeric) ? total.to_i : Integer(total, exception: false)
    return nil if total_i.nil?

    out = {
      'kind' => 'roll',
      'id' => id,
      'timestamp' => ts.is_a?(Numeric) ? ts : ts.to_i,
      'sessionId' => @schedule_id.to_s,
      'playerName' => h['playerName'].to_s.truncate(120),
      'characterName' => h['characterName'].to_s.truncate(120),
      'type' => type,
      'label' => label.truncate(500),
      'total' => total_i,
      'breakdown' => h['breakdown'].to_s.truncate(2_000),
    }

    rg = h['rollGroupId'].to_s
    out['rollGroupId'] = rg.truncate(MAX_ID_LENGTH) if rg.present?

    %w[d20 d20Alt advantage isNat20 isNat1 isCrit damageType].each do |key|
      next unless h.key?(key)

      out[key] = h[key]
    end

    if h['dice'].is_a?(Array)
      out['dice'] = h['dice'].filter_map { |x| x.is_a?(Numeric) ? x.to_i : Integer(x, exception: false) }.compact.first(40)
    end

    # Quebra de dano POR TIPO (arma + riders elementais) p/ o card exibir um chip
    # por tipo cross-device (ex.: concussão + fogo). Só em rolagens de dano.
    if type == 'damage'
      lines = sanitize_damage_lines(h['damageLines'])
      out['damageLines'] = lines if lines.present?
    end

    sr = h['senderRole'].to_s
    out['senderRole'] = sr if CHAT_ROLES.include?(sr)
    accent = sanitize_hex_color(h['cardAccentColor'])
    out['cardAccentColor'] = accent if accent.present?

    if type == 'attack'
      aho = h['attackHitOutcome'].to_s
      out['attackHitOutcome'] = aho if ATTACK_HIT_OUTCOMES.include?(aho)
    end

    # Card de PROMPT de teste de resistência (TR): substitui o modal. Preserva o
    # objeto `savePrompt` (sanitizado) para o card renderizar cross-device.
    if type == 'save' && h['savePrompt'].is_a?(Hash)
      sp = h['savePrompt'].stringify_keys
      dc = sp['dc']
      dc_i = dc.is_a?(Numeric) ? dc.to_i : Integer(dc, exception: false)
      if dc_i
        prompt = {
          'dc' => dc_i,
          'ability' => sp['ability'].to_s.slice(0, 8),
          'targetName' => sp['targetName'].to_s.truncate(120),
        }
        prompt['sourceName'] = sp['sourceName'].to_s.truncate(120) if sp['sourceName'].present?
        prompt['mode'] = sp['mode'] if %w[apply-on-fail remove-on-success].include?(sp['mode'].to_s)
        prompt['resolved'] = true if sp['resolved'] == true
        out['savePrompt'] = prompt
      end
    end

    out
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

    result
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
