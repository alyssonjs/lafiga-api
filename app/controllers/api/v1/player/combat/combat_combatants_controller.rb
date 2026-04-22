module Api::V1::Player::Combat
  # Endpoints dos combatentes (turn order).
  #
  #   GET    /schedules/:schedule_id/combat_combatants
  #   POST   /schedules/:schedule_id/combat_combatants
  #   PATCH  /schedules/:schedule_id/combat_combatants/:id
  #   DELETE /schedules/:schedule_id/combat_combatants/:id
  #   POST   /schedules/:schedule_id/combat_combatants/reorder
  #   POST   /schedules/:schedule_id/combat_combatants/:id/apply_damage
  #   POST   /schedules/:schedule_id/combat_combatants/:id/heal
  #   POST   /schedules/:schedule_id/combat_combatants/:id/record_death_save
  #
  # Leitura: membro do grupo OU DM.
  # Mutação: APENAS DM.
  class CombatCombatantsController < BaseController
    before_action :authorize_write!, except: [:index, :update]
    before_action :ensure_combat_state!, only: [:create, :reorder]
    before_action :set_combatant,
                  only: [:update, :destroy, :apply_damage, :heal, :record_death_save]
    before_action :authorize_combatant_update!, only: [:update]

    def index
      cs = @schedule.combat_state
      collection = cs ? cs.combat_combatants.order(:position) : []
      render json: { combatants: ::Combat::Serializers.combatants(collection) }, status: :ok
    end

    # Body: {
    #   combatant: {
    #     type: 'pc' | 'npc',
    #     combatable_id: <Character.id ou CombatNpc.id>,
    #     initiative: 15,
    #     initiative_bonus: 2,
    #     position: 0,        # opcional; default = append no fim
    #     # campos opcionais — se ausentes para PC, copia de Sheet
    #     hp_current, hp_max, ac, ...
    #   }
    # }
    def create
      attrs = combatant_params
      combatable = resolve_combatable(attrs[:type], attrs[:combatable_id])
      return render(json: { error: 'combatable inválido' }, status: :unprocessable_entity) unless combatable

      next_position = attrs[:position].presence&.to_i || (@combat_state.combat_combatants.maximum(:position).to_i + 1)
      defaults = defaults_for(combatable)

      build_attrs = {
        combat_state: @combat_state,
        combatable: combatable,
        position: next_position,
        name: attrs[:name].presence || defaults[:name],
        initiative: parse_initiative_param(attrs[:initiative]),
        initiative_bonus: attrs.key?(:initiative_bonus) ? attrs[:initiative_bonus].to_i : defaults[:initiative_bonus].to_i,
        tie_break_dex: attrs.key?(:tie_break_dex) ? attrs[:tie_break_dex].to_i : defaults[:tie_break_dex].to_i,
        hp_current: attrs[:hp_current].presence&.to_i || defaults[:hp_current],
        hp_max: attrs[:hp_max].presence&.to_i || defaults[:hp_max],
        ac: attrs[:ac].presence&.to_i || defaults[:ac],
        temp_hp: attrs[:temp_hp].presence&.to_i || 0,
      }

      combatant = CombatCombatant.new(build_attrs)
      if combatant.save
        ::Combat::Broadcaster.combatant_upserted(combatant)
        render json: { combatant: ::Combat::Serializers.combatant(combatant) }, status: :created
      else
        render json: { errors: combatant.errors.full_messages }, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordNotUnique
      render json: { error: 'position já ocupada — use reorder ou outro index' }, status: :conflict
    end

    def update
      combat_state = @combatant.combat_state
      if @combatant.update(combatant_update_params)
        if @combatant.saved_change_to_initiative? || @combatant.saved_change_to_tie_break_dex?
          ::Combat::SortInitiativePositionsService.call(combat_state: combat_state.reload)
          @combatant.reload
          ::Combat::Broadcaster.state_changed(combat_state.reload)
          combat_state.combat_combatants.order(:position).each do |c|
            ::Combat::Broadcaster.combatant_upserted(c)
          end
        else
          ::Combat::Broadcaster.combatant_upserted(@combatant)
        end
        render json: { combatant: ::Combat::Serializers.combatant(@combatant) }, status: :ok
      else
        render json: { errors: @combatant.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      cid = @combatant.id
      sid = @schedule.id
      @combatant.destroy!
      ::Combat::Broadcaster.combatant_destroyed(schedule_id: sid, combatant_id: cid)
      render json: { id: cid }, status: :ok
    end

    # Body: { ordered_combatant_ids: [12, 7, 9, ...] }
    def reorder
      result = ::Combat::ReorderService.call(
        combat_state: @combat_state,
        ordered_combatant_ids: params[:ordered_combatant_ids],
        current_user: @current_user,
      )
      if result.success?
        # Reorder muda position de TODOS — emite N upserts. Front consolida
        # via dedupe por id no reducer.
        result.result.each { |c| ::Combat::Broadcaster.combatant_upserted(c) }
        render json: { combatants: ::Combat::Serializers.combatants(result.result) }, status: :ok
      else
        render json: { errors: result.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # Body: { amount: 7 }
    def apply_damage
      result = ::Combat::DamageService.call(combatant: @combatant, amount: params[:amount], current_user: @current_user)
      if result.success?
        payload = result.result
        ::Combat::Broadcaster.combatant_upserted(payload[:combatant])
        render json: {
          combatant: ::Combat::Serializers.combatant(payload[:combatant]),
          damage_applied: payload[:damage_applied],
          concentration_check_required: payload[:concentration_check_required],
          concentration_dc: payload[:concentration_dc],
        }, status: :ok
      else
        render json: { errors: result.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # Body: { amount: 5 }
    def heal
      @combatant.heal!(params[:amount].to_i)
      ::Combat::Broadcaster.combatant_upserted(@combatant)
      render json: { combatant: ::Combat::Serializers.combatant(@combatant) }, status: :ok
    rescue ArgumentError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # Body: { kind: 'success' | 'failure' }
    def record_death_save
      @combatant.record_death_save!(params[:kind].to_s.to_sym)
      ::Combat::Broadcaster.combatant_upserted(@combatant)
      render json: { combatant: ::Combat::Serializers.combatant(@combatant) }, status: :ok
    rescue ArgumentError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def ensure_combat_state!
      @combat_state = @schedule.combat_state
      render(json: { error: 'inicie o combate antes' }, status: :unprocessable_entity) unless @combat_state
    end

    def set_combatant
      cs = @schedule.combat_state
      @combatant = cs&.combat_combatants&.find_by(id: params[:id])
      render(json: { error: 'combatant não encontrado' }, status: :not_found) unless @combatant
    end

    def combatant_params
      params.require(:combatant).permit(
        :type, :combatable_id, :name, :initiative, :initiative_bonus, :tie_break_dex, :position,
        :hp_current, :hp_max, :ac, :temp_hp,
      )
    end

    def combatant_update_params
      params.require(:combatant).permit(
        :name, :initiative, :initiative_bonus, :tie_break_dex, :hp_current, :hp_max, :ac, :temp_hp,
        :is_delayed, :is_concentrating, :concentration_spell, :is_stabilized, :is_dead,
        conditions: [[:id, :turns_left]],
        actions_used: [:action, :bonus_action, :movement, :reaction],
        death_saves: [:successes, :failures],
      ).tap do |p|
        # `permit` deixa `conditions` como array de Hashes restritos; converter
        # para array simples de Hash (string keys) para casar com o schema JSONB.
        p[:conditions] = p[:conditions].map { |c| c.to_h.transform_keys(&:to_s) } if p[:conditions]
        p[:actions_used] = p[:actions_used].to_h.transform_keys(&:to_s) if p[:actions_used]
        p[:death_saves]  = p[:death_saves].to_h.transform_keys(&:to_s)  if p[:death_saves]
      end
    end

    def resolve_combatable(type, id)
      case type.to_s
      when 'pc'  then Character.find_by(id: id)
      when 'npc' then CombatNpc.find_by(id: id, schedule_id: @schedule.id)
      end
    end

    def defaults_for(combatable)
      case combatable
      when Character
        sheet = combatable.sheet
        dex = character_dex_score(sheet)
        bonus = ((dex - 10) / 2.0).floor
        {
          name: combatable.name,
          hp_current: sheet&.hp_current.to_i,
          hp_max:     sheet&.hp_max.to_i,
          ac:         10, # combat profile virá depois (Fase 2 com sheet AC)
          initiative_bonus: bonus,
          tie_break_dex: dex,
        }
      when CombatNpc
        st = combatable.stats || {}
        raw = st['dex'] || st[:dex]
        dex = raw.to_i
        dex = 10 unless dex.positive?
        bonus = ((dex - 10) / 2.0).floor
        {
          name: combatable.name,
          hp_current: combatable.hp_current,
          hp_max:     combatable.hp_max,
          ac:         combatable.ac,
          initiative_bonus: bonus,
          tie_break_dex: dex,
        }
      else
        { name: 'Combatente', hp_current: 0, hp_max: 0, ac: 10, initiative_bonus: 0, tie_break_dex: 10 }
      end
    end

    def character_dex_score(sheet)
      return 10 unless sheet

      meta = sheet.metadata
      meta = meta.to_unsafe_h if meta.is_a?(ActionController::Parameters)
      meta = meta.deep_symbolize_keys if meta.is_a?(Hash)

      raw = meta&.dig(:abilities, :scores, :dex) || meta&.dig('abilities', 'scores', 'dex')
      dex = raw.to_i
      dex.positive? ? dex : 10
    end

    def parse_initiative_param(raw)
      return nil if raw.nil?
      return nil if raw == ''

      raw.to_i
    end

    def authorize_combatant_update!
      return if site_or_table_dm?
      return if player_setting_own_initiative_only?

      render json: { error: 'apenas o DM da mesa ou o mestre da plataforma pode mutar combatentes' }, status: :forbidden
    end

    # Jogador só pode definir iniciativa no próprio PC, uma vez (de nil → valor).
    def player_setting_own_initiative_only?
      return false unless @combatant.combatable_type == Character.name
      return false unless @combatant.combatable&.user_id == @current_user.id
      return false unless @combatant.initiative.nil?

      p = combatant_update_params.to_h
      keys = p.keys.map(&:to_s).sort
      return false unless keys == ['initiative']

      p.key?('initiative') && !p['initiative'].nil?
    end
  end
end
