module Api::V1::Player::Combat
  # Endpoints da INTERAÇÃO DE COMBATE activa (Fase 1 — disputa Empurrar/Agarrar).
  # A interação vive em `CombatState#active_interaction` (jsonb, 1:1 com Schedule)
  # e é sincronizada via ActionCable no mesmo `state_changed` que já propaga
  # `movement_ledger`/estado — assim o cliente do DEFENSOR recebe o prompt em
  # tempo real e filtra `pending_responders` localmente.
  #
  #   PUT    /schedules/:schedule_id/combat/active_interaction          # upsert (atacante propõe / rolou)
  #   POST   /schedules/:schedule_id/combat/active_interaction/respond  # defensor responde (defender_roll)
  #   DELETE /schedules/:schedule_id/combat/active_interaction          # clear (resolveu / cancelou)
  #
  # Leitura: já sai em `GET .../combat_state` (serializer `active_interaction`).
  # Mutação:
  #   - DM da mesa / mestre da plataforma / dono da campanha; OU
  #   - o jogador dono de um Character envolvido (source no upsert / character_id
  #     no respond). NPCs (`owned_by_dm`) sempre pelo DM.
  class InteractionsController < BaseController
    before_action :set_combat_state
    before_action :ensure_active_combat!, only: [:upsert, :respond]

    # PUT — corpo: { interaction: { kind:'contest', source_id, target_ids:[...],
    #   label?, attacker_roll? { total, ... }, pending_defender_owned_by_dm? } }
    def upsert
      ip = interaction_params
      payload =
        if ip['kind'].to_s == ::Combat::InteractionService::KIND_OPPORTUNITY_ATTACK
          ::Combat::InteractionService.build_opportunity_attack(ip)
        else
          ::Combat::InteractionService.build_contest(ip)
        end
      return render(json: { errors: 'interaction inválida' }, status: :unprocessable_entity) if payload.nil?

      return forbidden! unless authorized_to_initiate?(payload)

      @combat_state.set_active_interaction!(payload)
      @combat_state.reload
      ::Combat::Broadcaster.state_changed(@combat_state)
      render json: { active_interaction: @combat_state.active_interaction }, status: :ok
    end

    # POST :respond — corpo: { character_id, defender_roll: { skill, total, ... },
    #   attacker_roll? }. O responder deve estar em `pending_responders` e ainda
    #   não ter respondido.
    def respond
      current = @combat_state.active_interaction
      return render(json: { error: 'nenhuma interação activa' }, status: :unprocessable_entity) if current.blank?

      return forbidden! unless authorized_to_respond?(current, respond_params)

      return respond_opportunity_attack(current) if current['kind'] == ::Combat::InteractionService::KIND_OPPORTUNITY_ATTACK

      next_payload, err = ::Combat::InteractionService.apply_response(current, respond_params)
      if err
        return render(json: { error: respond_error_message(err) }, status: respond_error_status(err))
      end

      @combat_state.set_active_interaction!(next_payload)
      @combat_state.reload
      ::Combat::Broadcaster.state_changed(@combat_state)
      render json: { active_interaction: @combat_state.active_interaction }, status: :ok
    end

    # DELETE — limpa a interação activa (resolvida/cancelada). Idempotente:
    # devolve 200 com `null` mesmo se já estava vazia.
    def clear
      return forbidden! unless authorized_to_clear?

      @combat_state&.clear_active_interaction!
      @combat_state&.reload
      ::Combat::Broadcaster.state_changed(@combat_state) if @combat_state
      render json: { active_interaction: @combat_state&.active_interaction }, status: :ok
    end

    private

    def set_combat_state
      @combat_state = @schedule&.combat_state
    end

    def ensure_active_combat!
      return if @combat_state&.active?

      render json: { error: 'combat não está activo' }, status: :unprocessable_entity
    end

    def interaction_params
      params.require(:interaction).permit(
        :id, :kind, :source_id, :label, :pending_defender_owned_by_dm,
        target_ids: [],
        pending_responders: [:character_id, :need, :owned_by_dm, :responded],
        attacker_roll: [:total, :formula, :advantage, :skill, :roll_group_id, :natural20, :natural1, { dice: [] }],
        contest: [attacker_roll: [:total, :formula, :advantage, :skill, :roll_group_id, :natural20, :natural1, { dice: [] }]],
        opportunity_attack: [
          :mover_token_id, :mover_name, :mover_combatant_id,
          :reactor_token_id, :reactor_name,
          :ignores_disengage, :oa_at_disadvantage,
          # `attacks`/`npc_attacks` são listas de hashes descritivos (estrutura
          # aninhada como o `contest`); puxamos o conteúdo cru de forma segura
          # via `permitted_opportunity_attack_lists` (permit não cobre array de
          # hash arbitrário). Allowlist estrita aqui; o service só repassa hashes.
        ],
      ).to_h.tap do |p|
        lists = permitted_opportunity_attack_lists
        p[:opportunity_attack] = (p[:opportunity_attack] || {}).merge(lists) if lists.present?
      end
    end

    # `attacks`/`npc_attacks` vêm como arrays de hash livres (riders/parcelas de
    # dano que o front monta). `permit` não modela array de hash arbitrário sem
    # listar chaves, então puxamos o conteúdo cru e deixamos a normalização
    # estrita (só hashes) para o `InteractionService`.
    def permitted_opportunity_attack_lists
      oa = params.dig(:interaction, :opportunity_attack)
      return {} if oa.blank?

      out = {}
      %i[attacks npc_attacks].each do |key|
        raw = oa[key]
        next if raw.blank?

        arr = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h.values : Array(raw)
        out[key] = Array(arr).map { |h| h.respond_to?(:to_unsafe_h) ? h.to_unsafe_h : h }
      end
      out
    end

    def respond_params
      params.permit(
        :character_id, :defender_skill,
        defender_roll: [:total, :formula, :advantage, :skill, :roll_group_id, :natural20, :natural1, { dice: [] }],
        attacker_roll: [:total, :formula, :advantage, :skill, :roll_group_id, :natural20, :natural1, { dice: [] }],
        opportunity_attack: [:damage, :ignored, :hit, roll: [:total]],
      ).to_h
    end

    # Quem pode iniciar/limpar: DM da mesa OU dono de um PC `source` da interação.
    #
    # Exceção `opportunity_attack`: o DISPARO vem de QUEM MOVE, mas o `source_id`
    # é o REATOR → a regra "dono do source" barraria o mover. Para esse kind,
    # autorizamos o DM OU o dono do PC do TURNO ATUAL (o mover). Conservador: só
    # para `opportunity_attack`; `contest` segue inalterado.
    def authorized_to_initiate?(payload)
      return true if site_or_table_dm?

      if payload['kind'] == ::Combat::InteractionService::KIND_OPPORTUNITY_ATTACK
        return current_turn_belongs_to_user?
      end

      owns_character?(payload['source_id'])
    end

    def authorized_to_clear?
      return true if site_or_table_dm?
      current = @combat_state&.active_interaction
      return false if current.blank?
      owns_character?(current['source_id'])
    end

    # Quem pode responder: DM (resolve NPCs/`owned_by_dm`) OU dono do PC
    # `character_id` que está em `pending_responders`.
    def authorized_to_respond?(current, rp)
      return true if site_or_table_dm?

      character_id = rp['character_id'].to_s
      responder = Array(current['pending_responders']).find { |r| r['character_id'].to_s == character_id }
      return false if responder.nil?
      return false if responder['owned_by_dm'] == true

      owns_character?(character_id)
    end

    # `source_id`/`character_id` são characterIds (string). Confirma que o
    # Character pertence ao usuário corrente.
    def owns_character?(character_id)
      return false if character_id.to_s.empty?

      char = Character.find_by(id: character_id)
      char&.user_id == @current_user.id
    end

    def forbidden!
      render json: { error: 'sem permissão para esta interação de combate' }, status: :forbidden
    end

    # --- Ataque de Oportunidade (respond server-side) --------------------------

    # Ramo OA do respond (F0 — base loop-free). Server-side fecha DOIS gaps:
    #   1) auth: o REATOR age FORA do próprio turno, então o DANO é aplicado AQUI
    #      (não confiamos no cliente p/ mutar o HP do mover).
    #   2) loop: ao resolver, a interação é LIMPA SERVER-SIDE
    #      (`active_interaction` → nil) — antes ela ficava em `phase:'resolved'`
    #      e dependia de ALGUM cliente disparar o DELETE; quando o cliente certo
    #      não estava presente, travava/loopava. Agora o feed também sai do
    #      backend (`log_oa_resolved`), não do efeito de resolução do front.
    #
    # `with_lock` (SELECT FOR UPDATE) serializa contra corrida (dois responds /
    # respond vs clear). Idempotente: se a interação já foi limpa (nil) ou o
    # responder já respondeu, devolve o estado corrente sem reaplicar dano.
    #
    # `ignored:true` = o reator abriu mão da reação → NÃO consome reação, NÃO
    # aplica dano; apenas limpa a interação e loga a desistência.
    def respond_opportunity_attack(current)
      mover_cc = nil
      reactor_cc = nil
      log_data = nil
      damage_applied = false
      reaction_consumed = false

      @combat_state.with_lock do
        @combat_state.reload
        current = @combat_state.active_interaction

        # Idempotência: a interação já foi resolvida/limpa (nil/resolved) ou o
        # responder já respondeu → não reaplica dano nem reação.
        if current.blank? || current['phase'] == 'resolved' || oa_responder_already_responded?(current)
          return render json: { active_interaction: @combat_state.active_interaction }, status: :ok
        end

        ignore = ActiveModel::Type::Boolean.new.cast(respond_params.dig('opportunity_attack', 'ignored'))
        # ACERTO/ERRO é DECISÃO DO MESTRE (V/X no chat), não mais comparação vs CA.
        # `hit:true` acertou; `hit:false` errou. Compat. legado: quando `hit`
        # ausente, cai no comportamento antigo (roll >= CA do mover).
        hit_param = respond_params.dig('opportunity_attack', 'hit')

        next_payload, err = ::Combat::InteractionService.apply_response(current, respond_params)
        if err
          return render(json: { error: respond_error_message(err) }, status: respond_error_status(err))
        end

        oa = next_payload['opportunity_attack'] || {}
        mover_cc = resolve_mover_combatant(next_payload)
        return render(json: { error: 'mover combatant não encontrado' }, status: :unprocessable_entity) if mover_cc.nil?

        mover_ac   = mover_cc.ac.to_i
        roll_total = oa.dig('roll', 'total').to_i
        damage     = oa['damage'].to_i
        outcome =
          if hit_param.nil?
            roll_total >= mover_ac ? 'hit' : 'miss'   # legado (sem decisão do Mestre)
          else
            ActiveModel::Type::Boolean.new.cast(hit_param) ? 'hit' : 'miss'
          end

        reactor_cc = resolve_reactor_combatant(next_payload)

        # Dano: só quando NÃO ignorou, o Mestre confirmou ACERTO e há dano > 0.
        if !ignore && outcome == 'hit' && damage.positive?
          result = ::Combat::DamageService.call(combatant: mover_cc, amount: damage, current_user: @current_user)
          if result.success?
            mover_cc = result.result[:combatant]
            damage_applied = true
          end
        end

        # Reação consumida pelo REATOR só quando NÃO ignorou (ignorar = não
        # reagiu → não gasta reação). Server-side, persiste.
        if !ignore && reactor_cc
          au = Hash(reactor_cc.actions_used).merge('reaction' => true)
          reactor_cc.update(actions_used: au)
          reaction_consumed = true
        end

        # Dados p/ o log server-side (capturados antes de sair do lock).
        log_data = {
          mover_name:    mover_cc.name.to_s,
          reactor_name:  reactor_cc&.name.to_s.presence || oa['reactor_name'].to_s,
          roll_total:    roll_total,
          mover_ac:      mover_ac,
          damage:        damage,
          outcome:       outcome,
          ignore:        ignore,
        }

        # F0 — LIMPA server-side (active_interaction → nil) em vez de persistir
        # `phase:'resolved'`. Idempotente via `clear_active_interaction!`.
        @combat_state.clear_active_interaction!
      end

      @combat_state.reload
      # Ordem: combatant_upserted (mover, se dano) → state_changed (já com
      # active_interaction=nil) → log_appended (feed server-side).
      ::Combat::Broadcaster.combatant_upserted(mover_cc) if mover_cc && damage_applied
      ::Combat::Broadcaster.combatant_upserted(reactor_cc) if reactor_cc && reaction_consumed
      ::Combat::Broadcaster.state_changed(@combat_state)
      log_oa_resolved(@schedule, log_data) if log_data
      render json: { active_interaction: @combat_state.active_interaction }, status: :ok
    end

    # Cria a linha do feed (SessionLog kind combat) do OA resolvido e a propaga
    # via `Broadcaster.log_appended`. O feed sai do BACKEND (o front NÃO deve
    # logar no efeito de resolução). Defensivo: no-op sem schedule/dados.
    def log_oa_resolved(schedule, data)
      return if schedule.blank? || data.blank?

      mover   = data[:mover_name].to_s.presence || 'Alvo'
      reactor = data[:reactor_name].to_s.presence || 'Reator'

      # O Mestre decide V/X no chat — o texto não cita a CA (a decisão é do
      # Mestre, não da comparação roll vs CA).
      message =
        if data[:ignore]
          "🛡️ #{reactor} abriu mão da reação contra #{mover}."
        elsif data[:outcome] == 'hit'
          "⚔️ #{reactor} reagiu ao movimento de #{mover}: ACERTOU — #{data[:damage]} de dano."
        else
          "⚔️ #{reactor} reagiu ao movimento de #{mover}: ERROU."
        end

      log = schedule.session_logs.new(kind: :combat, actor: reactor, message: message)
      return unless log.save

      ::Combat::Broadcaster.log_appended(log)
    end

    # O responder do OA já respondeu? (idempotência adicional à fase).
    def oa_responder_already_responded?(current)
      character_id = respond_params['character_id'].to_s
      responder = Array(current['pending_responders']).find { |r| r['character_id'].to_s == character_id }
      responder && [true, 1, '1', 'true'].include?(responder['responded'])
    end

    # Resolve o CombatCombatant do MOVER. Preferência:
    #   1) `opportunity_attack.mover_combatant_id` (id do CombatCombatant), quando presente;
    #   2) `target_ids.first` casado contra `id` do CombatCombatant; senão
    #   3) `target_ids.first` casado contra `combatable_id` (characterId / npcId).
    def resolve_mover_combatant(payload)
      oa = payload['opportunity_attack'] || {}

      mcid = oa['mover_combatant_id']
      if mcid.present?
        cc = @combat_state.combat_combatants.find_by(id: mcid)
        return cc if cc
      end

      resolve_combatant_by_identity(Array(payload['target_ids']).first)
    end

    # Resolve o CombatCombatant do REATOR via `source_id` (reator identity).
    def resolve_reactor_combatant(payload)
      resolve_combatant_by_identity(payload['source_id'])
    end

    # Casa um identity (string) contra `id` do CombatCombatant e, em fallback,
    # contra `combatable_id` (characterId / combat_npc id).
    def resolve_combatant_by_identity(identity)
      return nil if identity.blank?

      @combat_state.combat_combatants.find_by(id: identity) ||
        @combat_state.combat_combatants.find_by(combatable_id: identity)
    end

    def respond_error_message(err)
      {
        not_found: 'nenhuma interação activa',
        invalid_character: 'character_id ausente',
        not_pending: 'este personagem não está pendente nesta interação',
        invalid_roll: 'defender_roll inválido',
        invalid_skill: 'perícia de defesa inválida',
      }.fetch(err, 'resposta inválida')
    end

    def respond_error_status(err)
      err == :not_found ? :unprocessable_entity : :unprocessable_entity
    end
  end
end
