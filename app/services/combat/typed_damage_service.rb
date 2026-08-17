module Combat
  # Aplica um ATAQUE MULTI-PARCELA (várias parcelas tipadas: perfurante + fogo +
  # elétrico…) respeitando resistência / imunidade / vulnerabilidade POR TIPO do
  # ALVO — SERVER-AUTHORITATIVE. Resolve o bug de multiplayer: o cliente do
  # ATACANTE não tem a ficha do alvo, mas o SERVIDOR tem (summary = defesas de
  # raça + itens equipados + feats via CharacterSheetSummaryService).
  #
  # Mitiga cada parcela pelo seu tipo (via `DamageMitigationRules`), SOMA, e
  # aplica o total UMA vez (`apply_damage!` absorve PV temporário + trata morte
  # 1×). Death saves e concentração sobre o total FINAL. Devolve o breakdown por
  # tipo (p/ o card de dano no chat) + total.
  #
  # `extra_resistances/immunities`: tipos CONDICIONAIS computados no front
  # (Fúria / Cicatriz Ritualística / Despertar Elemental) que dependem do
  # `turnState` do combatente — UNIDOS às defesas da ficha antes da mitigação.
  class TypedDamageService
    prepend SimpleCommand

    def initialize(combatant:, parcels:, current_user: nil, attack_kind: 'normal',
                   extra_resistances: [], extra_immunities: [])
      @combatant    = combatant
      @parcels      = Array(parcels)
      @current_user = current_user
      @attack_kind  = attack_kind.to_s
      @extra_resistances = Array(extra_resistances).map { |r| DamageMitigationRules.normalize(r) }.compact
      @extra_immunities  = Array(extra_immunities).map  { |r| DamageMitigationRules.normalize(r) }.compact
    end

    def call
      return errors.add(:combatant, 'inexistente') && nil if @combatant.nil?

      normalized = @parcels.map { |p| normalize_parcel(p) }.reject { |p| p[:amount].zero? && p[:damage_type].nil? }
      return errors.add(:parcels, 'vazio') && nil if normalized.empty?
      return errors.add(:parcels, 'amount deve ser >= 0') && nil if normalized.any? { |p| p[:amount].negative? }

      # ⚠️ SOB LOCK a partir daqui: `apply_damage!` decrementa do `hp_current`
      # CARREGADO EM MEMÓRIA. Dois danos concorrentes no MESMO combatente liam o
      # mesmo HP e a última escrita vencia — o outro dano SUMIA.
      #
      # Caso real (16/08): Melodia Flamejante com o dado no dano disparou duas
      # aplicações no mesmo instante (32 base + 5 do dado) num alvo com 22 PV.
      # Resultado gravado: 22−5 = 17, com os 32 perdidos. Vale para qualquer
      # concorrência — dano em área, dois atacantes, rider + base.
      @combatant.with_lock do
        was_concentrating = @combatant.is_concentrating

        # Coleta as defesas do alvo UMA vez (força o summary — há vários tipos) e
        # une as resistências/imunidades condicionais vindas do front.
        mods = DamageMitigationRules.collect_defenses(@combatant, force_summary: true)
        mods[:resistances] |= @extra_resistances
        mods[:immunities]  |= @extra_immunities

        applied = normalized.map do |p|
          DamageMitigationRules.mitigate_parcel(p[:amount], p[:damage_type], p[:magical], mods)
        end

        final_total = applied.sum { |a| a[:final] }
        raw_total   = normalized.sum { |p| p[:amount] }

        # PHB p. 197 — alvo PC a 0 HP atingido: +1 falha de death save (crítico +2).
        # ANTES do apply_damage! (estado relevante = "0 HP no momento do ataque").
        death_save_failures_added = compute_death_save_failures_from_attack
        death_save_failures_added.times { @combatant.record_death_save!(:failure) }

        @combatant.apply_damage!(final_total)

        next {
          combatant: @combatant,
          damage_applied: final_total,
          damage_raw: raw_total,
          breakdown: applied, # [{ damage_type:, raw:, final:, modifier: }]
          attack_kind: @attack_kind,
          death_save_failures_added: death_save_failures_added,
          concentration_check_required: was_concentrating && final_total.positive? && !@combatant.is_dead,
          concentration_dc: was_concentrating && final_total.positive? ? [10, final_total / 2].max : nil,
        }
      end
    rescue ArgumentError => e
      errors.add(:base, e.message)
      nil
    end

    private

    # Aceita hash com chaves string OU símbolo (params) e sanitiza tipos.
    def normalize_parcel(p)
      h = p.respond_to?(:to_unsafe_h) ? p.to_unsafe_h : p
      get = ->(k) { h[k] || h[k.to_s] }
      {
        amount: get.call(:amount).to_i,
        damage_type: get.call(:damage_type).presence,
        magical: ActiveModel::Type::Boolean.new.cast(get.call(:magical)),
      }
    end

    def compute_death_save_failures_from_attack
      return 0 unless @combatant.combatable_type == 'Character'
      return 0 unless @combatant.hp_current.to_i == 0
      return 0 if @combatant.is_dead
      @attack_kind == 'critical' ? 2 : 1
    end
  end
end
