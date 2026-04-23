# frozen_string_literal: true

# Ephemeral session feed (chat + dice bubble) over ActionCable.
# Subscribe: { channel: 'SessionFeedChannel', schedule_id:, token: }
# Client perform: feed_item with { item: <FeedItem hash> }
#
# No DB persistence — one broadcast per valid item. Rate-limited per user/schedule.
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

    ActionCable.server.broadcast(self.class.stream_name_for(@schedule_id), normalized)
  end

  private

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

    sr = h['senderRole'].to_s
    out['senderRole'] = sr if CHAT_ROLES.include?(sr)
    accent = sanitize_hex_color(h['cardAccentColor'])
    out['cardAccentColor'] = accent if accent.present?

    out
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
