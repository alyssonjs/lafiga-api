# frozen_string_literal: true

module Combat
  # Resolve um pendingTargetSave de DANO como um unico comando atomico.
  #
  # O cliente envia somente a face do d20 e a identidade do pending. CD, bonus,
  # dano, tipo e regra de metade ficam no turn_state persistido. A mesma trava de
  # linha cobre validacao, mitigacao, HP, limpeza do pending e log, portanto duas
  # abas/aparelhos nao conseguem aplicar o mesmo dano duas vezes.
  class PendingSaveResolutionService
    prepend SimpleCommand

    PENDING_KEY = 'pendingTargetSave'
    BARDIC_KEY = 'bardicInspiration'
    BARDIC_PENDING_KEY = 'pendingBardicInspiration'
    AUTO_FAIL_CONDITIONS = %w[paralyzed petrified stunned unconscious].freeze
    CONDITION_ALIASES = {
      'paralisado' => 'paralyzed',
      'petrificado' => 'petrified',
      'atordoado' => 'stunned',
      'inconsciente' => 'unconscious',
    }.freeze

    def initialize(combatant:, current_user:, d20:, save_id:, card_roll_group_id: nil, bardic_bonus: nil,
                   d20_alt: nil, advantage: nil)
      @combatant = combatant
      @current_user = current_user
      @d20 = d20.to_i
      # Vantagem/desvantagem no TR imposto (ex.: Cancao de Protecao do Bardo).
      # O cliente rola AS DUAS faces e diz o modo; QUEM ESCOLHE e o servidor —
      # senao bastaria mandar sempre a face boa dizendo que houve vantagem.
      @d20_alt = d20_alt.present? ? d20_alt.to_i : nil
      @advantage = %w[advantage disadvantage].include?(advantage.to_s) ? advantage.to_s : 'normal'
      @save_id = save_id.to_s
      @card_roll_group_id = card_roll_group_id.to_s.presence
      # Inspiração Bárdica somada ao TR (a regra deixa decidir depois de ver o d20).
      # O valor vem do cliente, mas quem MANDA é o servidor: só é aceito se o alvo
      # realmente carrega o dado, é limitado pelas faces dele, e o dado é consumido
      # na MESMA transação — assim um eco atrasado não devolve um dado já gasto.
      @bardic_bonus = bardic_bonus.to_i
    end

    def call
      return reject(:combatant, 'inexistente') if @combatant.nil?
      return reject(:save_id, 'obrigatorio') if @save_id.blank?

      payload = nil
      @combatant.with_lock do
        @combatant.reload
        pending = current_pending

        return reject(:conflict, 'o teste pendente ja foi resolvido ou substituido') unless pending
        return reject(:conflict, 'o teste pendente foi substituido') unless pending['saveId'].to_s == @save_id
        if @card_roll_group_id.present? && pending['cardRollGroupId'].to_s != @card_roll_group_id
          return reject(:conflict, 'o card do teste pendente foi substituido')
        end
        return reject(:authorization, 'usuario nao controla o alvo, a fonte ou a mesa') unless authorized?(pending)
        return reject(:pending, 'este endpoint resolve apenas testes pendentes com dano') unless pending.key?('aoeDamage')

        auto_fail = auto_fail?(pending['ability'])
        unless auto_fail || (1..20).cover?(@d20)
          return reject(:d20, 'deve estar entre 1 e 20')
        end
        if @d20_alt && !auto_fail && !(1..20).cover?(@d20_alt)
          return reject(:d20_alt, 'deve estar entre 1 e 20')
        end

        bardic = bardic_inspiration_bonus
        return reject(:bardic_bonus, 'sem dado de Inspiração Bárdica para somar') if @bardic_bonus.positive? && bardic.zero?

        save = resolve_save(pending, auto_fail: auto_fail, bardic_bonus: bardic)
        damage_result = apply_damage(resolve_damage_parcels(pending, save))
        raise ActiveRecord::Rollback unless damage_result

        next_turn_state = Hash(@combatant.turn_state).deep_dup
        next_turn_state.delete(PENDING_KEY)
        if bardic.positive?
          next_turn_state.delete(BARDIC_KEY)
          next_turn_state.delete(BARDIC_PENDING_KEY)
        end
        if damage_result[:damage_applied].positive?
          next_turn_state['rageTookDamageSinceLastTurn'] = true
        end
        @combatant.update!(turn_state: next_turn_state)

        log = create_resolution_log!(pending, save, damage_result)
        resolve_feed_card!(pending)

        payload = {
          combatant: @combatant,
          log: log,
          save: save,
          save_id: pending['saveId'].to_s,
          card_roll_group_id: pending['cardRollGroupId'].to_s.presence,
          damage_applied: damage_result[:damage_applied],
          damage_raw: damage_result[:damage_raw],
          breakdown: damage_result[:breakdown],
          death_save_failures_added: damage_result[:death_save_failures_added],
          concentration_check_required: damage_result[:concentration_check_required],
          concentration_dc: damage_result[:concentration_dc],
        }
      end

      payload
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
      reject(:base, e.message)
    end

    private

    def reject(key, message)
      errors.add(key, message)
      nil
    end

    def current_pending
      value = Hash(@combatant.turn_state)[PENDING_KEY]
      value.is_a?(Hash) ? value.stringify_keys : nil
    end

    def authorized?(pending)
      return true if site_or_table_dm?
      return true if target_owned_by_user?

      source = source_combatant(pending['sourceCombatantId'])
      source&.combatable_type == Character.name && source.combatable&.user_id == @current_user&.id
    end

    def site_or_table_dm?
      return false unless @current_user

      schedule = @combatant.combat_state.schedule
      Group.user_is_dm?(@current_user) || schedule.group&.dm_user_id == @current_user.id
    end

    def target_owned_by_user?
      @combatant.combatable_type == Character.name &&
        @combatant.combatable&.user_id == @current_user&.id
    end

    def source_combatant(public_id)
      match = /\A(?:pc|npc)-(\d+)\z/.match(public_id.to_s)
      return nil unless match

      @combatant.combat_state.combat_combatants.find_by(id: match[1].to_i)
    end

    def auto_fail?(ability)
      return false unless %w[str dex].include?(ability.to_s)

      Array(@combatant.conditions).any? do |row|
        raw = row.is_a?(Hash) ? (row['id'] || row[:id]) : row
        AUTO_FAIL_CONDITIONS.include?(canonical_condition(raw))
      end
    end

    def canonical_condition(raw)
      normalized = I18n.transliterate(raw.to_s).downcase.strip
      CONDITION_ALIASES.fetch(normalized, normalized)
    end

    # Bônus EFETIVO da Inspiração: 0 quando não há dado, e nunca acima das faces
    # dele (o cliente pede, o servidor limita).
    def bardic_inspiration_bonus
      return 0 unless @bardic_bonus.positive?

      insp = Hash(@combatant.turn_state)[BARDIC_KEY]
      return 0 unless insp.is_a?(Hash)

      faces = insp['die'].to_s[/\d+/].to_i
      return 0 if faces.zero?

      [@bardic_bonus, faces].min
    end

    def resolve_save(pending, auto_fail:, bardic_bonus: 0)
      chosen, dropped, mode = choose_face(auto_fail: auto_fail)
      d20 = auto_fail ? 0 : chosen
      # PENALIDADE imposta pela fonte (ex.: dado de Inspiracao da Antifona do
      # Bardo Busca da Cancao): SUBTRAI do TR. Fica separada do `saveBonus` de
      # proposito — somar as duas esconderia a penalidade do jogador, que
      # precisa ver POR QUE o teste ficou mais dificil.
      penalty = [pending['savePenalty'].to_i, 0].max
      bonus = pending['saveBonus'].to_i + bardic_bonus - penalty
      total = auto_fail ? 0 : d20 + bonus
      critical_failure = !auto_fail && d20 == 1
      critical_success = !auto_fail && d20 == 20
      success = !auto_fail && !critical_failure && (critical_success || total >= pending['dc'].to_i)

      out = {
        d20: d20,
        save_bonus: bonus,
        total: total,
        dc: pending['dc'].to_i,
        success: success,
        auto_fail: auto_fail,
        critical_failure: critical_failure,
        critical_success: critical_success,
        advantage: mode,
        save_penalty: penalty,
        breakdown: auto_fail ? 'falha automatica' : format_breakdown(d20, bonus, total, dropped: dropped),
      }
      out[:d20_alt] = dropped if dropped
      out
    end

    # Face escolhida, face descartada e modo EFETIVO. Sem a 2a face o modo cai
    # para 'normal' — um dado so nao vira vantagem por decreto do cliente.
    def choose_face(auto_fail:)
      return [0, nil, 'normal'] if auto_fail
      return [@d20, nil, 'normal'] if @d20_alt.nil? || @advantage == 'normal'

      chosen = @advantage == 'advantage' ? [@d20, @d20_alt].max : [@d20, @d20_alt].min
      dropped = chosen == @d20 ? @d20_alt : @d20
      [chosen, dropped, @advantage]
    end

    def format_breakdown(d20, bonus, total, dropped: nil)
      sign = bonus >= 0 ? "+#{bonus}" : bonus.to_s
      faces = dropped ? "[#{d20}] (descartado #{dropped})" : "[#{d20}]"
      "#{faces}#{sign} = #{total}"
    end

    # Parcelas TIPADAS do dano de area, ja com o veredito do TR aplicado.
    #
    # Uma magia pode causar mais de um tipo (Antifona do Trovao e do Relampago:
    # 4d8 trovejante + 4d6 eletrico). Somar tudo num tipo so quebraria a
    # mitigacao — um alvo resistente a eletrico pagaria cheio pelos dois.
    #
    # O veredito vale POR PARCELA (a metade arredonda para baixo em cada uma),
    # e nao no total: assim os chips por tipo do card SOMAM exatamente o total
    # aplicado, sem sobra de arredondamento a explicar na mesa.
    def resolve_damage_parcels(pending, save)
      parcels = [{ amount: [pending['aoeDamage'].to_i, 0].max, type: pending['aoeDamageType'].presence }]
      Array(pending['aoeExtraDamage']).each do |extra|
        next unless extra.is_a?(Hash)

        parcels << { amount: [extra['amount'].to_i, 0].max, type: extra['type'].presence }
      end

      half = ActiveModel::Type::Boolean.new.cast(pending['aoeHalfOnSave'])
      parcels.filter_map do |parcel|
        amount = verdict_amount(parcel[:amount], save, half: half)
        next if amount.zero?

        { amount: amount, damage_type: parcel[:type], magical: true }
      end
    end

    def verdict_amount(amount, save, half:)
      return amount * 2 if save[:critical_failure]
      return 0 if save[:critical_success]
      return amount unless save[:success]

      half ? amount / 2 : 0
    end

    def apply_damage(parcels)
      if parcels.empty?
        return {
          damage_applied: 0,
          damage_raw: 0,
          breakdown: [],
          death_save_failures_added: 0,
          concentration_check_required: false,
          concentration_dc: nil,
        }
      end

      result = Combat::TypedDamageService.call(
        combatant: @combatant,
        parcels: parcels,
        current_user: @current_user,
        attack_kind: 'normal',
        extra_resistances: runtime_resistances,
      )
      unless result.success?
        result.errors.full_messages.each { |message| errors.add(:damage, message) }
        return nil
      end

      result.result
    end

    # Defesas temporarias pertencem ao estado persistido do combate, nao ao
    # browser que respondeu ao TR. Furia base concede B/P/S sem armadura pesada;
    # Cicatrizes guarda seus tipos e rodadas diretamente no turn_state.
    def runtime_resistances
      turn_state = Hash(@combatant.turn_state)
      out = []

      scars = turn_state['scarResistances']
      if scars.is_a?(Hash)
        scars.each do |damage_type, rounds|
          out << damage_type if rounds.to_i.positive?
        end
      end

      if turn_state.key?('rageRoundsRemaining') && barbarian? && !wearing_heavy_armor?
        out.concat(%w[contundente perfurante cortante])
      end

      out.concat(wayfinder_refrain_resistances(turn_state))

      out.uniq
    end

    # Refrao de Desbravador (Bardo Busca da Cancao L6): o ALVO carrega o buff no
    # proprio turn_state, com validade por RODADA ABSOLUTA. O mapa cancao ->
    # resistencias e DADO, espelhando `WAYFINDER_REFRAIN_BENEFITS` do front.
    #
    # ⚠️ Precisa existir AQUI: o TR de area e resolvido no servidor, entao um
    # Refrao so no TypeScript nao protegeria ninguem em multiplayer.
    WAYFINDER_REFRAIN_RESISTANCES = {
      'melodia-flamejante' => %w[fogo],
      'cancao-de-reestruturacao' => ['concussao (nao-magico)', 'cortante (nao-magico)',
                                     'perfurante (nao-magico)'],
      'cantico-da-perda-gelida' => %w[frio],
      'cancao-da-vida' => %w[necrotico],
      'antifona-do-trovao-e-do-relampago' => %w[relampago trovejante],
      'balada-do-ressurgimento-agoniante' => %w[acido veneno],
    }.freeze

    # ⚠️ Refroes sao CUMULATIVOS (houserule 16/08 — a fonte manda substituir), por
    # isso o valor e uma LISTA. Aceita tambem o formato ANTIGO (um Hash so):
    # havia buff em campo quando o formato mudou, e ignora-lo apagaria uma
    # resistencia ja paga com acao bonus.
    def wayfinder_refrain_resistances(turn_state)
      raw = turn_state['wayfinderRefrain']
      entries = raw.is_a?(Array) ? raw : [raw]
      round = @combatant.combat_state.round.to_i

      entries.flat_map do |refrain|
        next [] unless refrain.is_a?(Hash)
        # Rodada ABSOLUTA: expirado nao protege, mesmo que o buff ainda esteja no
        # turn_state (a limpeza e preguicosa de proposito).
        next [] unless round < refrain['expiresAtRound'].to_i

        WAYFINDER_REFRAIN_RESISTANCES.fetch(refrain['songId'].to_s, [])
      end
    end

    def barbarian?
      sheet = @combatant.combatable_type == Character.name ? @combatant.combatable&.sheet : nil
      sheet&.sheet_klasses&.any? { |row| row.klass&.api_index.to_s.include?('barbar') }
    end

    def wearing_heavy_armor?
      mods = Combat::DamageMitigationRules.collect_defenses(@combatant, force_summary: true)
      ActiveModel::Type::Boolean.new.cast(mods[:wearing_heavy_armor])
    rescue StandardError
      false
    end

    MITIGATION_LABELS = {
      resistant: 'resistencia',
      immune: 'imunidade',
      vulnerable: 'vulnerabilidade',
    }.freeze

    # "22 fogo -> 11 (resistencia)" — so das parcelas que a defesa MUDOU.
    #
    # ⚠️ Sem isto o log dizia apenas "sofre 11 de dano" e a mesa nao tinha como
    # saber se a resistencia entrou: 11 e tanto "22 com resistencia" quanto
    # "metade num TR bem-sucedido". Visto em campo (16/08) com o Refrao de
    # Desbravador — a mitigacao estava CERTA e parecia bug.
    def mitigation_note(damage_result)
      changed = Array(damage_result[:breakdown]).select do |row|
        MITIGATION_LABELS.key?(row[:modifier]&.to_sym)
      end
      return '' if changed.empty?

      parts = changed.map do |row|
        "#{row[:raw]} #{row[:damage_type]} → #{row[:final]} " \
          "(#{MITIGATION_LABELS[row[:modifier].to_sym]})"
      end
      " [#{parts.join(', ')}]"
    end

    def create_resolution_log!(pending, save, damage_result)
      target_name = @combatant.name.to_s.sub(/^\[[^\]]+\]\s*/, '')
      source_name = pending['sourceLabel'].presence || pending['sourceActorName'].presence || 'efeito'
      emoji = pending['emoji'].presence || '🎲'
      verdict = save[:success] ? 'passa' : 'falha'
      message =
        "#{emoji} #{target_name} #{verdict} no TR de #{pending['ability'].to_s.upcase} " \
        "de #{source_name} (#{save[:total]} vs CD #{save[:dc]}) → sofre " \
        "#{damage_result[:damage_applied]} de dano#{mitigation_note(damage_result)}."

      @combatant.combat_state.schedule.session_logs.create!(
        kind: :combat,
        actor: target_name,
        message: message,
      )
    end

    def resolve_feed_card!(pending)
      roll_group_id = pending['cardRollGroupId'].to_s.presence
      return unless roll_group_id

      SessionFeed::Persist.resolve_save_prompt(
        schedule_id: @combatant.combat_state.schedule_id,
        roll_group_id: roll_group_id,
      )
    end
  end
end
