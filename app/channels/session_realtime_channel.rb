# Canal único da sessão de jogo. Carrega TODO o estado realtime (combat_state,
# combatants, npcs, session_logs) num só stream `session_<schedule_id>` para
# que o front se inscreva uma vez e receba qualquer mutação.
#
# Cada mensagem broadcast tem o shape canônico:
#   {
#     event: 'state_changed' | 'combatant_upserted' | 'combatant_destroyed' |
#            'npc_upserted'   | 'npc_destroyed'     | 'log_appended',
#     payload: { ... }   # serialização correspondente em Combat::Serializers
#     emitted_at: ISO8601
#   }
#
# AUTH (mesma régua dos controllers HTTP):
#   - JWT obrigatório (`params[:token]`), validado pelo mesmo JsonWebToken +
#     ValidateJwtToken da camada HTTP.
#   - Read-access: qualquer utilizador autenticado (hub; espelha combat BaseController).
#   - Não exposto: este channel é READ-ONLY do front; mutações vão pelos
#     endpoints REST. Por isso não há `def receive(data)` aqui.
#
# Convenção do stream name: `session_#{schedule_id}` — usado tanto pelo
# subscribe quanto pelo Combat::Broadcaster.
class SessionRealtimeChannel < ApplicationCable::Channel
  STREAM_PREFIX = 'session_'.freeze

  def self.stream_name_for(schedule_id)
    "#{STREAM_PREFIX}#{schedule_id}"
  end

  def subscribed
    token = params[:token].to_s
    @current_user = authenticate_token(token)
    return reject unless @current_user

    @schedule = Schedule.find_by(id: params[:schedule_id])
    return reject unless @schedule
    return reject unless can_read?(@schedule, @current_user)

    stream_from self.class.stream_name_for(@schedule.id)
  end

  def unsubscribed
    # Hook reservado para Fase 1D (presence). Por ora, no-op.
  end

  private

  def authenticate_token(token)
    return nil if token.blank?
    return nil if ValidateJwtToken.where(token: token).exists?

    payload = JsonWebToken.decode(token)
    uid = payload[:user_id] || payload[:id]
    User.find_by(id: uid)
  rescue ExceptionHandler::InvalidToken, JWT::DecodeError, StandardError
    nil
  end

  def can_read?(schedule, user)
    user.present?
  end
end
