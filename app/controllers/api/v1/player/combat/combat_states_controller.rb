module Api::V1::Player::Combat
  # Endpoints do estado global de combate (singleton 1:1 com Schedule).
  #
  #   GET    /api/v1/player/schedules/:schedule_id/combat_state          # show
  #   POST   /api/v1/player/schedules/:schedule_id/combat_state/begin    # iniciar (ou reiniciar)
  #   POST   /api/v1/player/schedules/:schedule_id/combat_state/finish   # encerrar
  #   POST   /api/v1/player/schedules/:schedule_id/combat_state/advance_turn
  #   POST   /api/v1/player/schedules/:schedule_id/combat_state/set_round
  #
  # Leitura: qualquer membro do grupo OU DM.
  # Mutação: DM site-wide, dono da campanha (`group.dm_user_id`), ou (só em
  # `advance_turn`) o jogador dono do PC do turno ativo.
  class CombatStatesController < BaseController
    before_action :authorize_write!, only: [:begin, :finish, :advance_turn, :set_round]
    before_action :set_combat_state, only: [:show, :finish, :advance_turn, :set_round]

    # GET — devolve o combat_state existente (se houver). Retorna 200 com null
    # quando nunca foi iniciado, em vez de 404, para o front decidir mostrar
    # "Iniciar Combate" sem precisar fazer rescue de erro.
    def show
      render json: { combat_state: Combat::Serializers.state(@combat_state) }, status: :ok
    end

    # POST :begin — usa CombatStartService (find_or_create + sync HP).
    def begin
      result = ::Combat::StartService.call(schedule: @schedule, current_user: @current_user)
      if result.success?
        render json: { combat_state: Combat::Serializers.state(result.result) }, status: :ok
      else
        render json: { errors: result.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # POST :finish — usa CombatEndService (sync HP back + finish).
    def finish
      return render(json: { error: 'combat_state inexistente' }, status: :unprocessable_entity) unless @combat_state

      result = ::Combat::EndService.call(schedule: @schedule, current_user: @current_user)
      if result.success?
        render json: { combat_state: Combat::Serializers.state(result.result) }, status: :ok
      else
        render json: { errors: result.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # POST :advance_turn — protegido por with_lock (G5). Idempotente para
    # estados inativos (no-op).
    def advance_turn
      return render(json: { error: 'combat_state inexistente' }, status: :unprocessable_entity) unless @combat_state

      unless all_living_have_initiative?(@combat_state)
        return render(
          json: { error: 'aguarde todas as iniciativas serem roladas antes de passar o turno' },
          status: :unprocessable_entity,
        )
      end

      upsert_ids = @combat_state.advance_turn!
      @combat_state.reload
      ::Combat::Broadcaster.state_changed(@combat_state)
      Array(upsert_ids).each { |c| ::Combat::Broadcaster.combatant_upserted(c) }
      render json: { combat_state: ::Combat::Serializers.state(@combat_state) }, status: :ok
    end

    # POST :set_round — usado pelo DM para corrigir manualmente o round.
    # Body: { round: <int> }
    def set_round
      return render(json: { error: 'combat_state inexistente' }, status: :unprocessable_entity) unless @combat_state

      @combat_state.set_round!(params[:round].to_i)
      @combat_state.reload
      ::Combat::Broadcaster.state_changed(@combat_state)
      render json: { combat_state: ::Combat::Serializers.state(@combat_state) }, status: :ok
    rescue ArgumentError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def set_combat_state
      @combat_state = @schedule.combat_state
    end

    def all_living_have_initiative?(cs)
      cs.combat_combatants.where(is_dead: false).all? { |c| !c.initiative.nil? }
    end
  end
end
