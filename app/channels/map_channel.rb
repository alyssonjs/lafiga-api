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
    reject and return unless @current_user

    @battle_map = BattleMap.find_by(id: params[:map_id])
    reject and return unless @battle_map
    reject and return unless @battle_map.readable_by?(@current_user)

    stream_from stream_name_for(@battle_map)
  end

  def unsubscribed
    # nada — broadcaster nao mantem presence (por enquanto)
  end

  def self.stream_name(map_or_id)
    id = map_or_id.respond_to?(:id) ? map_or_id.id : map_or_id
    "map_#{id}"
  end

  private

  def stream_name_for(map)
    self.class.stream_name(map)
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
