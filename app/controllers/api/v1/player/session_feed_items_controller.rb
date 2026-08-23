module Api::V1::Player
  # Histórico do feed da sessão (chat + dice rolls).
  #
  #   GET /api/v1/player/schedules/:schedule_id/session_feed_items
  #     ?limit=50            # default 50, max 200
  #     &before=<iso8601>    # cursor temporal (mais antigo que <iso8601>)
  #     &before_id=<int>     # tie-breaker estável (junto com before)
  #
  # Resposta: { items: [<payload>...], meta: { count, has_more, next_cursor } }
  # `next_cursor`: { before: <iso8601>, before_id: <int> } ou nil quando esgota.
  #
  # Items vêm em ordem cronológica DESCENDENTE (mais recente primeiro). O
  # cliente reordena para render (chat sobe items mais novos no scroll bottom).
  #
  # Autorização (espelha SessionFeedChannel#can_read?): qualquer usuário
  # autenticado pode ler. Rolagens usam POST com ACK; ActionCable distribui
  # somente o resultado já persistido.
  class SessionFeedItemsController < ApplicationController
    before_action :authorize_request
    before_action :set_schedule

    DEFAULT_LIMIT = 50
    MAX_LIMIT = 200

    def index
      limit = sanitize_limit(params[:limit])

      audiencias = SessionFeed::Audience.readable(@schedule, @current_user)

      scope = SessionFeedItem
        .where(schedule_id: history_schedule_ids)
        .for_audiences(audiencias)
        .recent_first

      if params[:before].present?
        begin
          before_time = Time.iso8601(params[:before])
          before_id   = params[:before_id].to_i
          scope = scope.before_cursor(before_time, before_id)
        rescue ArgumentError
          # before malformado: trata como sem cursor (devolve mais recentes)
        end
      end

      records = scope.limit(limit + 1).to_a
      has_more = records.size > limit
      page = records.first(limit)

      next_cursor =
        if has_more && page.last
          { before: page.last.posted_at.iso8601(3), before_id: page.last.id }
        end

      render json: {
        items: page.map(&:payload),
        meta: {
          count: page.size,
          has_more: has_more,
          next_cursor: next_cursor,
          # Quais canais este usuário tem. É o SERVIDOR que decide — se o
          # cliente adivinhasse, mostraria uma aba cujo envio seria recusado.
          audiences: audiencias,
        },
      }, status: :ok
    end

    # POST /api/v1/player/schedules/:schedule_id/session_feed_items
    # body: { item: <DiceRollEvent> }
    #
    # `item.id` é a chave idempotente. Retry, segunda aba ou timeout devolvem o
    # primeiro resultado persistido em vez de executar uma segunda rolagem.
    def create
      raw_item = params[:item]
      raw_item = raw_item.to_unsafe_h if raw_item.is_a?(ActionController::Parameters)
      normalized = SessionFeed::RollNormalizer.call(schedule_id: @schedule.id, item: raw_item)
      return render(json: { error: 'rolagem inválida' }, status: :unprocessable_entity) unless normalized

      unless SessionFeed::RateLimit.allow?(
        @current_user.id,
        @schedule.id,
        bucket: 'roll-command',
        limit: 120,
      )
        return render json: { error: 'muitas rolagens; tente novamente' }, status: :too_many_requests
      end

      trace = Realtime::Telemetry.request_context(request)
      client_id = trace[:client_id] || Realtime::Telemetry.identifier(raw_item['clientId'])
      command_id = trace[:command_id] ||
        Realtime::Telemetry.identifier(raw_item['commandId']) ||
        Realtime::Telemetry.identifier(normalized['rollGroupId']) ||
        Realtime::Telemetry.identifier(normalized['id'])
      normalized['clientId'] = client_id if client_id
      normalized['commandId'] = command_id if command_id
      normalized['eventId'] = SecureRandom.uuid

      Realtime::Telemetry.emit(
        stage: 'command_received', domain: 'feed', event_type: 'roll',
        command_id: command_id, client_id: client_id,
        aggregate_type: 'schedule', aggregate_id: @schedule.id,
        actor_id: @current_user.id, outcome: 'pending',
      )

      record = SessionFeed::Persist.call(schedule_id: @schedule.id, normalized: normalized)
      unless record&.persisted?
        Realtime::Telemetry.emit(
          stage: 'command_failed', domain: 'feed', event_type: 'roll',
          command_id: command_id, client_id: client_id,
          aggregate_type: 'schedule', aggregate_id: @schedule.id,
          actor_id: @current_user.id, outcome: 'failed', error_class: 'persistence_failed',
        )
        return render json: { error: 'não foi possível confirmar a rolagem' }, status: :service_unavailable
      end

      authoritative = record.payload
      ActionCable.server.broadcast(SessionFeedChannel.stream_name_for(@schedule.id), authoritative)
      Realtime::Telemetry.emit(
        stage: 'command_acknowledged', domain: 'feed', event_type: 'roll',
        event_id: authoritative['eventId'], command_id: command_id, client_id: client_id,
        aggregate_type: 'schedule', aggregate_id: @schedule.id,
        actor_id: @current_user.id, outcome: 'succeeded',
      )

      render json: {
        item: authoritative,
        realtime: {
          commandId: authoritative['commandId'],
          clientId: authoritative['clientId'],
          eventId: authoritative['eventId'],
        }.compact,
      }, status: :ok
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      Rails.logger.warn(
        { event: 'session_feed.roll_command_failed', schedule_id: @schedule&.id,
          error: e.class.name, message: e.message }.to_json,
      )
      render json: { error: 'não foi possível confirmar a rolagem' }, status: :service_unavailable
    end

    private

    # O chat NÃO recomeça do zero a cada sessão.
    #
    # O feed é gravado por `schedule`, mas a conversa é da MESA: ao abrir a
    # sessão seguinte o grupo perdia tudo o que tinha combinado, e o caderno do
    # Mestre ia junto. A leitura passa a varrer as sessões do mesmo grupo; a
    # escrita continua a cair na sessão atual, então nada muda de dono.
    def history_schedule_ids
      group_id = @schedule.group_id
      return [@schedule.id] if group_id.blank?

      Schedule.where(group_id: group_id).pluck(:id)
    end

    def set_schedule
      @schedule = Schedule.find_by(id: schedule_id_param)
      render(json: { error: 'schedule não encontrado' }, status: :not_found) unless @schedule
    end

    # Aceita prefixo `api-NN` para alinhar com o uso do front (scheduleAdapters).
    def schedule_id_param
      raw = params[:schedule_id]
      if raw.is_a?(String) && raw.match?(/\Aapi-\d+\z/i)
        raw.sub(/\Aapi-/i, '')
      else
        raw
      end
    end

    def sanitize_limit(raw)
      n = raw.to_i
      return DEFAULT_LIMIT if n <= 0
      [n, MAX_LIMIT].min
    end
  end
end
