## MapChannel
##
## ActionCable channel para sincronizacao realtime de um BattleMap entre
## DMs/players da mesma campanha. Cliente subscreve em:
##
##   { channel: 'MapChannel', map_id: <id>, token: '<jwt>' }
##
## Auth: mesmo padrao do ChatChannel (JWT em params[:token] +
## ValidateJwtToken para revogacao). Visibilidade reusa o
## `BattleMap#readable_by?` (DM ve tudo, owner ve o seu, membros do grupo
## veem mapas compartilhados).
##
## Stream nominado `map_<id>` para que `MapRealtime::Broadcaster` (Fase C2)
## possa publicar com `ActionCable.server.broadcast("map_#{id}", ...)`.
class MapChannel < ApplicationCable::Channel
  def subscribed
    token = params[:token].to_s
    @current_user = authenticate_token(token)
    unless @current_user
      trace_realtime(
        stage: 'subscription_rejected', domain: 'map', outcome: 'rejected',
        aggregate_type: 'battle_map', aggregate_id: params[:map_id], error_class: 'authentication_failed'
      )
      reject and return
    end

    @battle_map = BattleMap.find_by(id: params[:map_id])
    unless @battle_map
      trace_realtime(
        stage: 'subscription_rejected', domain: 'map', outcome: 'rejected',
        aggregate_type: 'battle_map', aggregate_id: params[:map_id], error_class: 'aggregate_not_found'
      )
      reject and return
    end
    unless @battle_map.readable_by?(@current_user)
      trace_realtime(
        stage: 'subscription_rejected', domain: 'map', outcome: 'rejected',
        aggregate_type: 'battle_map', aggregate_id: @battle_map.id, error_class: 'authorization_failed'
      )
      reject and return
    end

    # `schedule_id` isola a mesa. Só é aceito se o utilizador puder VER a sessão
    # — senão bastaria adivinhar um id para escutar os eventos de outra mesa.
    @schedule_id = resolve_schedule_id(params[:schedule_id])

    stream_from stream_name_for(@battle_map, @schedule_id)
    trace_realtime(
      stage: 'subscription_confirmed', domain: 'map', outcome: 'succeeded',
      aggregate_type: 'battle_map', aggregate_id: @battle_map.id
    )
  end

  # @return [Integer, nil] nil = canal base (Map Builder / cliente antigo)
  def resolve_schedule_id(raw)
    return nil if raw.blank?

    schedule = Schedule.find_by(id: raw)
    return nil unless schedule&.viewable_by?(@current_user)
    # Assinar a sessão de um mapa que não é o dela também não faz sentido.
    return nil unless schedule.battle_map_id == @battle_map.id ||
                      ScheduleBattleMap.exists?(schedule_id: schedule.id, battle_map_id: @battle_map.id)

    schedule.id
  end

  def unsubscribed
    trace_realtime(
      stage: 'subscription_removed', domain: 'map', outcome: 'succeeded',
      aggregate_type: 'battle_map', aggregate_id: @battle_map&.id || params[:map_id]
    )
  end

  # Um canal por (mapa, sessão). Sem sessão (Map Builder) fica o canal base.
  # Sem isto, duas mesas no mesmo mapa recebem os eventos uma da outra — o
  # token movido numa aparece na outra, ao vivo.
  def self.stream_name(map_or_id, schedule_id = nil)
    id = map_or_id.respond_to?(:id) ? map_or_id.id : map_or_id
    sid =
      if schedule_id.present?
        schedule_id
      elsif map_or_id.respond_to?(:session_scope_schedule_id)
        map_or_id.session_scope_schedule_id
      end

    sid.present? ? "map_#{id}_s#{sid}" : "map_#{id}"
  end

  private

  def stream_name_for(map, schedule_id = nil)
    self.class.stream_name(map, schedule_id)
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
end
