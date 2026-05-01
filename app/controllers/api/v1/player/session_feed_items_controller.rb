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
  # autenticado pode ler — mesma regra do hub. Endpoint só de leitura;
  # writes seguem via ActionCable.
  class SessionFeedItemsController < ApplicationController
    before_action :authorize_request
    before_action :set_schedule

    DEFAULT_LIMIT = 50
    MAX_LIMIT = 200

    def index
      limit = sanitize_limit(params[:limit])

      scope = @schedule.session_feed_items.recent_first

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
        },
      }, status: :ok
    end

    private

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
