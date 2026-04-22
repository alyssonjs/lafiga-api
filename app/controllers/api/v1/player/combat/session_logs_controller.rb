module Api::V1::Player::Combat
  # Feed cronológico da sessão (narrativa, combat, rolls, etc).
  #
  #   GET    /schedules/:schedule_id/session_logs
  #   POST   /schedules/:schedule_id/session_logs
  #
  # Leitura: membro do grupo OU DM.
  # Criação: TAMBÉM membro do grupo OU DM — players precisam postar rolls de
  # dados no feed (kind=roll). Abuso é controlado socialmente (campanha
  # privada). Restrição mais fina (player só pode criar kind=roll do próprio
  # personagem) fica como TODO se necessário.
  class SessionLogsController < BaseController
    before_action :authorize_log_create!, only: [:create]

    # `?since=ISO8601`  → logs criados depois desta data (polling/sync)
    # `?limit=N`        → cap (default 200)
    # `?kind=roll,note` → filtro por kind(s)
    def index
      scope = @schedule.session_logs.recent_first

      if params[:since].present?
        begin
          scope = scope.where('created_at > ?', Time.iso8601(params[:since]))
        rescue ArgumentError
          # ignora since malformado — devolve a lista completa
        end
      end

      if params[:kind].present?
        kinds = Array(params[:kind]).flat_map { |k| k.to_s.split(',') } & SessionLog.kinds.keys
        scope = scope.where(kind: kinds) if kinds.any?
      end

      limit = [params[:limit].to_i.positive? ? params[:limit].to_i : 200, 500].min
      render json: { logs: ::Combat::Serializers.logs(scope.limit(limit)) }, status: :ok
    end

    def create
      log = @schedule.session_logs.new(log_params)
      log.actor ||= default_actor_for(@current_user)

      if log.save
        ::Combat::Broadcaster.log_appended(log)
        render json: { log: ::Combat::Serializers.log(log) }, status: :created
      else
        render json: { errors: log.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    # Escrita no feed: só DM ou membro do grupo (leitura hub continua aberta no BaseController).
    def authorize_log_create!
      return if Group.user_is_dm?(@current_user)
      return if @schedule.group&.member?(@current_user)

      render json: { error: 'não autorizado a registar no log desta sessão' }, status: :forbidden
    end

    def log_params
      params.require(:log).permit(
        :kind, :actor, :message, :posted_at,
        roll_result: [:expression, :total, :breakdown, :modifier, :critical, :fumble],
      ).tap do |p|
        p[:roll_result] = p[:roll_result].to_h.transform_keys(&:to_s) if p[:roll_result]
      end
    end

    def default_actor_for(user)
      char = user.characters.where(group_id: @schedule.group_id).first
      char&.name || user.name.presence || user.username
    end
  end
end
