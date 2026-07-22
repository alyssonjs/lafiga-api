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
    before_action :authorize_write!, except: [:index, :update, :record_death_save]
    before_action :ensure_combat_state!, only: [:create, :reorder]
    before_action :set_combatant,
                  only: [:update, :destroy, :apply_damage, :heal, :record_death_save]
    before_action :authorize_combatant_update!, only: [:update]
    before_action :authorize_record_death_save!, only: [:record_death_save]

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

    # Body: { amount: 7, damage_type?: 'cortante', magical?: false, attack_kind?: 'normal'|'critical' }
    # `damage_type`/`magical` habilitam a mitigação tipada + Heavy Armor Master no
    # DamageService. Ausentes → dano cheio (:normal), compat retroativa.
    def apply_damage
      result = ::Combat::DamageService.call(
        combatant: @combatant,
        amount: params[:amount],
        current_user: @current_user,
        damage_type: params[:damage_type].presence,
        magical: ActiveModel::Type::Boolean.new.cast(params[:magical]),
        attack_kind: params[:attack_kind].presence || 'normal',
      )
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

    # Fase 6F — Body: { passed: bool, dc: Integer (opcional, p/ broadcast) }
    # Resolve o concentration save após apply_damage. Se passed=false:
    #   - seta is_concentrating=false
    #   - emite broadcast `concentration_broken` para a UI
    # Se passed=true: apenas confirma (sem mudança).
    def record_concentration_save
      passed = ActiveModel::Type::Boolean.new.cast(params[:passed])
      dc     = params[:dc].present? ? params[:dc].to_i : nil
      spell  = @combatant.concentration_spell

      if passed
        render json: { combatant: ::Combat::Serializers.combatant(@combatant), passed: true, dc: dc }, status: :ok
      else
        @combatant.update!(is_concentrating: false, concentration_spell: nil)
        ::Combat::Broadcaster.concentration_broken(@combatant, spell_name: spell, dc: dc)
        ::Combat::Broadcaster.combatant_upserted(@combatant)
        render json: { combatant: ::Combat::Serializers.combatant(@combatant), passed: false, dc: dc }, status: :ok
      end
    end

    # Fase 6D — Body: { slot_level: Integer, spell_name: 'Hold Person' (opcional) }
    # Decrementa o spell_slots_used da SheetRuntimeState do PC e cria
    # SessionLog para o front exibir. NPCs não consomem slots (têm spell DCs
    # mas não slot tracking — usam "/dia" próprio).
    def cast_spell
      if @combatant.combatable_type != 'Character'
        return render(json: { error: 'apenas PCs consomem spell slots no tracker' },
                      status: :unprocessable_entity)
      end

      sheet = @combatant.combatable&.sheet
      return render(json: { error: 'PC sem ficha vinculada' }, status: :unprocessable_entity) unless sheet

      result = ::Combat::CastSpellService.call(
        sheet: sheet,
        slot_level: params[:slot_level].to_i,
        spell_name: params[:spell_name].presence
      )
      if result.success?
        ::Combat::Broadcaster.combatant_upserted(@combatant)
        render json: {
          combatant: ::Combat::Serializers.combatant(@combatant),
          runtime: result.result[:runtime].as_payload
        }, status: :ok
      else
        render json: { errors: result.errors.full_messages }, status: :unprocessable_entity
      end
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

        # turn_state — válvula genérica OPACA: aceita JSON aninhado arbitrário.
        # `permit(turn_state: {})` só liberaria um nível, então puxamos o hash
        # cru via to_unsafe_h (espelha o tratamento dos demais jsonb acima).
        if params.dig(:combatant, :turn_state)
          ts = params[:combatant][:turn_state]
          p[:turn_state] = ts.respond_to?(:to_unsafe_h) ? ts.to_unsafe_h : ts
        end
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
        # Tenta consumir o summary (que já agrega feats: Alerta init, AC bonus,
        # speed bonus, etc.). Se falhar (sheet nil ou erro), cai no caminho
        # legado com DEX cru. Comportamento backward-compatible.
        sd = build_combat_defaults_from_summary(sheet)
        if sd
          { name: combatable.name }.merge(sd)
        else
          dex = character_dex_score(sheet)
          {
            name: combatable.name,
            hp_current: sheet&.hp_current.to_i,
            hp_max:     sheet&.hp_max.to_i,
            ac:         10,
            initiative_bonus: ((dex - 10) / 2.0).floor,
            tie_break_dex: dex,
          }
        end
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

    # Constrói defaults de combat a partir do CharacterSheetSummaryService —
    # único local que consolida feats + raça + classe + equipamento. Antes
    # do fix da Fase 5, defaults_for usava DEX cru e AC=10 hardcoded, ignorando
    # Alerta (+5 init), Mestre de Armas Duplas (+1 CA), etc.
    #
    # Retorna `nil` quando o summary não pode ser construído — caller usa
    # caminho legado.
    def build_combat_defaults_from_summary(sheet)
      return nil unless sheet&.id

      cmd = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
      return nil unless cmd&.success?

      summary = cmd.result
      scores = summary.dig(:abilities, :scores) || {}
      dex = (scores[:dex] || scores['dex']).to_i
      dex = 10 unless dex.positive?

      # Iniciativa = (DEX-10)/2 + soma de modifiers de feats sobre 'initiative'
      # (FeatProducer.alerta_initiative_bonus, etc.).
      base_ini = ((dex - 10) / 2.0).floor
      feat_ini = (summary.dig(:modifiers, :initiative_bonus) ||
                  summary.dig(:modifiers, :feat_initiative_bonus) || 0).to_i

      # AC vive em summary[:equipment][:ac][:ac] (estrutura do
      # CharacterSheetSummaryService, agregando armadura + feats + estilo de
      # luta + itens mágicos). Fallback 10 (nu, sem AC).
      ac = (summary.dig(:equipment, :ac, :ac) || 10).to_i
      ac = 10 if ac < 1

      {
        hp_current: sheet.hp_current.to_i,
        hp_max:     sheet.hp_max.to_i,
        ac:         ac,
        initiative_bonus: base_ini + feat_ini,
        tie_break_dex: dex,
      }
    rescue StandardError
      nil
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

    # Campos de ESTADO DE TURNO que o DONO do PC pode mutar no próprio
    # combatente. São válvulas controladas pelo front (gasto de ação/bônus/
    # movimento/reação e estado opaco de turno). NÃO inclui campos sensíveis
    # (hp, ac, temp_hp, conditions, death_saves, is_dead, ...) — esses
    # continuam exclusivos do DM.
    PLAYER_TURN_STATE_FIELDS = %w[actions_used turn_state].freeze

    # Campos de EFEITO DE COMBATE (dano/cura + transição de morte derivada) que o
    # JOGADOR DO TURNO ATUAL pode aplicar em QUALQUER combatente — habilita
    # poção/ataque/magia do jogador. A regra "curado de 0 volta à batalha" exige
    # a transição completa (hp + condições + death saves + estabilizado + morto),
    # toda derivada no front por `deriveHpTransition`. Escopo: só no turno do
    # próprio PC e combate ativo; auditável pelo log de combate.
    COMBAT_EFFECT_FIELDS = %w[
      hp_current hp_max temp_hp conditions death_saves is_stabilized is_dead
      is_concentrating concentration_spell
    ].freeze

    def authorize_combatant_update!
      return if site_or_table_dm?
      return if player_setting_own_initiative_only?
      return if player_updating_own_turn_state?
      return if player_applying_combat_effect_on_own_turn?

      render json: { error: 'apenas o DM da mesa ou o mestre da plataforma pode mutar combatentes' }, status: :forbidden
    end

    # Teste de morte: DM sempre; jogador só grava o teste do PRÓPRIO combatente
    # (PC dele) e só quando é o turno desse combatente. Espelha o padrão de
    # efeitos de combate no próprio turno. NPC fica exclusivamente com o DM.
    def authorize_record_death_save!
      return if site_or_table_dm?
      # Jogador só grava o teste de morte do PRÓPRIO combatente, e só quando é o turno dele.
      return if current_turn_belongs_to_user? && current_turn_combatant&.id == @combatant&.id

      render json: { error: 'apenas o DM ou o dono do PC no próprio turno pode gravar teste de morte' }, status: :forbidden
    end

    # Jogador DONO do combatente do TURNO ATUAL pode aplicar efeitos de combate
    # (dano/cura) em qualquer combatente. Conservador: valida a lista EXATA de
    # chaves enviadas contra COMBAT_EFFECT_FIELDS (nada fora disso passa).
    def player_applying_combat_effect_on_own_turn?
      return false unless current_turn_belongs_to_user?

      p = combatant_update_params.to_h
      keys = p.keys.map(&:to_s)
      return false if keys.empty?

      (keys - COMBAT_EFFECT_FIELDS).empty?
    end

    # Jogador só pode definir iniciativa no próprio PC, uma vez (de nil → valor).
    def player_setting_own_initiative_only?
      return false unless player_owns_combatant?
      return false unless @combatant.initiative.nil?

      p = combatant_update_params.to_h
      keys = p.keys.map(&:to_s).sort
      return false unless keys == ['initiative']

      p.key?('initiative') && !p['initiative'].nil?
    end

    # Dono do PC pode atualizar APENAS os campos de estado de turno do próprio
    # combatente (allowlist em PLAYER_TURN_STATE_FIELDS). Qualquer chave fora
    # da allowlist (hp, ac, conditions, is_dead, etc.) cai fora e o jogador
    # recebe 403 — só o DM toca nesses. Conservador por design: validamos a
    # lista EXATA de chaves enviadas, não apenas a presença das permitidas.
    def player_updating_own_turn_state?
      return false unless player_owns_combatant?

      p = combatant_update_params.to_h
      keys = p.keys.map(&:to_s)
      return false if keys.empty?

      (keys - PLAYER_TURN_STATE_FIELDS).empty?
    end

    # O combatente é um PC cujo personagem pertence ao usuário autenticado.
    def player_owns_combatant?
      return false unless @combatant.combatable_type == Character.name

      @combatant.combatable&.user_id == @current_user.id
    end
  end
end
