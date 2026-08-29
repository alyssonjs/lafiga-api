module Api::V1::Player::Combat
  # CRUD de NPCs vivos da sessão (vida-curta: persistem por uma sessão).
  #
  #   GET    /schedules/:schedule_id/combat_npcs
  #   POST   /schedules/:schedule_id/combat_npcs
  #   PATCH  /schedules/:schedule_id/combat_npcs/:id
  #   DELETE /schedules/:schedule_id/combat_npcs/:id
  #   POST   /schedules/:schedule_id/combat_npcs/:id/defeat
  #   POST   /schedules/:schedule_id/combat_npcs/:id/revive
  #
  # Leitura: membro do grupo OU DM.
  # Mutação: APENAS DM.
  class CombatNpcsController < BaseController
    # `summon` tem autorizacao PROPRIA (dono do personagem), no servico.
    before_action :authorize_write!, except: [:index, :show, :summon]
    before_action :set_npc, only: [:show, :update, :destroy, :defeat, :revive]

    # `?include_defeated=1` para incluir derrotados; default mostra só vivos.
    def index
      scope = include_defeated? ? @schedule.combat_npcs : @schedule.combat_npcs.alive
      render json: { npcs: ::Combat::Serializers.npcs(scope.order(:name)) }, status: :ok
    end

    def show
      render json: { npc: ::Combat::Serializers.npc(@npc) }, status: :ok
    end

    def create
      npc = @schedule.combat_npcs.new(npc_params)
      if npc.save
        ::Combat::Broadcaster.npc_upserted(npc)
        render json: { npc: ::Combat::Serializers.npc(npc) }, status: :created
      else
        render json: { errors: npc.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # POST /schedules/:schedule_id/combat_npcs/summon
    # body: { character_id, companion_id }
    #
    # Traz o familiar/invocado da ficha para o tracker COM DONO — e por isso
    # nao passa pelo `create`, que e so-DM. A autorizacao (ser dono do
    # personagem, o companion estar na ficha dele) vive no servico.
    def summon
      npc = ::Combat::SummonCompanionService.new(
        schedule: @schedule,
        character: Character.find_by(id: params[:character_id]),
        companion_id: params[:companion_id],
        user: @current_user,
      ).call
      ::Combat::Broadcaster.npc_upserted(npc)
      render json: { npc: ::Combat::Serializers.npc(npc) }, status: :created
    rescue ::Combat::SummonCompanionService::Erro => e
      render json: { error: e.message }, status: :forbidden
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    def update
      if @npc.update(npc_params)
        ::Combat::Broadcaster.npc_upserted(@npc)
        render json: { npc: ::Combat::Serializers.npc(@npc) }, status: :ok
      else
        render json: { errors: @npc.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      nid = @npc.id
      sid = @schedule.id
      @npc.destroy!
      ::Combat::Broadcaster.npc_destroyed(schedule_id: sid, npc_id: nid)
      render json: { id: nid }, status: :ok
    end

    def defeat
      @npc.defeat!
      ::Combat::Broadcaster.npc_upserted(@npc)
      render json: { npc: ::Combat::Serializers.npc(@npc) }, status: :ok
    end

    def revive
      @npc.revive!
      ::Combat::Broadcaster.npc_upserted(@npc)
      render json: { npc: ::Combat::Serializers.npc(@npc) }, status: :ok
    end

    private

    def set_npc
      @npc = @schedule.combat_npcs.find_by(id: params[:id])
      render(json: { error: 'NPC não encontrado' }, status: :not_found) unless @npc
    end

    def include_defeated?
      ActiveModel::Type::Boolean.new.cast(params[:include_defeated])
    end

    def npc_params
      params.require(:npc).permit(
        :name, :hp_current, :hp_max, :ac, :base_ac, :speed, :cr,
        :proficiency_bonus, :monster_id, :notes,
        stats: {}, saving_throws: {}, skills: {}, equipment: {},
        attacks: [[:name, :attack_bonus, :damage_dice, :damage_type, :reach, :range, :description, :uses]],
      ).tap do |p|
        p[:stats]          = p[:stats].to_h.transform_keys(&:to_s)          if p[:stats]
        p[:saving_throws]  = p[:saving_throws].to_h.transform_keys(&:to_s)  if p[:saving_throws]
        p[:skills]         = p[:skills].to_h.transform_keys(&:to_s)         if p[:skills]
        p[:equipment]      = p[:equipment].to_h.transform_keys(&:to_s)      if p[:equipment]
        p[:attacks]        = p[:attacks].map { |a| a.to_h.transform_keys(&:to_s) } if p[:attacks]
      end
    end
  end
end
