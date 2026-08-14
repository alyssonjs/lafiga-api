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
    AUTO_FAIL_CONDITIONS = %w[paralyzed petrified stunned unconscious].freeze
    CONDITION_ALIASES = {
      'paralisado' => 'paralyzed',
      'petrificado' => 'petrified',
      'atordoado' => 'stunned',
      'inconsciente' => 'unconscious',
    }.freeze

    def initialize(combatant:, current_user:, d20:, save_id:, card_roll_group_id: nil)
      @combatant = combatant
      @current_user = current_user
      @d20 = d20.to_i
      @save_id = save_id.to_s
      @card_roll_group_id = card_roll_group_id.to_s.presence
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

        save = resolve_save(pending, auto_fail: auto_fail)
        damage_before_mitigation = resolve_damage_before_mitigation(pending, save)
        damage_result = apply_damage(pending, damage_before_mitigation)
        raise ActiveRecord::Rollback unless damage_result

        next_turn_state = Hash(@combatant.turn_state).deep_dup
        next_turn_state.delete(PENDING_KEY)
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

    def resolve_save(pending, auto_fail:)
      d20 = auto_fail ? 0 : @d20
      bonus = pending['saveBonus'].to_i
      total = auto_fail ? 0 : d20 + bonus
      critical_failure = !auto_fail && d20 == 1
      critical_success = !auto_fail && d20 == 20
      success = !auto_fail && !critical_failure && (critical_success || total >= pending['dc'].to_i)

      {
        d20: d20,
        save_bonus: bonus,
        total: total,
        dc: pending['dc'].to_i,
        success: success,
        auto_fail: auto_fail,
        critical_failure: critical_failure,
        critical_success: critical_success,
        breakdown: auto_fail ? 'falha automatica' : format_breakdown(d20, bonus, total),
      }
    end

    def format_breakdown(d20, bonus, total)
      sign = bonus >= 0 ? "+#{bonus}" : bonus.to_s
      "[#{d20}]#{sign} = #{total}"
    end

    def resolve_damage_before_mitigation(pending, save)
      group_damage = [pending['aoeDamage'].to_i, 0].max
      return group_damage * 2 if save[:critical_failure]
      return 0 if save[:critical_success]
      return group_damage unless save[:success]

      ActiveModel::Type::Boolean.new.cast(pending['aoeHalfOnSave']) ? group_damage / 2 : 0
    end

    def apply_damage(pending, amount)
      if amount.zero?
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
        parcels: [{
          amount: amount,
          damage_type: pending['aoeDamageType'].presence,
          magical: true,
        }],
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

      out.uniq
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

    def create_resolution_log!(pending, save, damage_result)
      target_name = @combatant.name.to_s.sub(/^\[[^\]]+\]\s*/, '')
      source_name = pending['sourceLabel'].presence || pending['sourceActorName'].presence || 'efeito'
      emoji = pending['emoji'].presence || '🎲'
      verdict = save[:success] ? 'passa' : 'falha'
      message =
        "#{emoji} #{target_name} #{verdict} no TR de #{pending['ability'].to_s.upcase} " \
        "de #{source_name} (#{save[:total]} vs CD #{save[:dc]}) → sofre " \
        "#{damage_result[:damage_applied]} de dano."

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
