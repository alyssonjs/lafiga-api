module Combat
  # Regras de mitigação de dano por tipo (resistência / imunidade /
  # vulnerabilidade + reduções fixas do Heavy Armor Master) e COLETA das
  # defesas do alvo. Extraído do `DamageService` (parcela única) para ser
  # COMPARTILHADO com o `TypedDamageService` (multi-parcela) sem duplicar a
  # lógica. Métodos recebem tipo/magical EXPLÍCITOS (sem estado de instância),
  # então servem tanto p/ 1 tipo quanto p/ N parcelas.
  #
  # PHB 5e p. 197: imune → 0 · resistente → metade (round down, min 0) ·
  # vulnerável → dobro · reduções fixas (HAM) ANTES da divisão por resistência.
  module DamageMitigationRules
    module_function

    # Dano físico (B/P/S) reduzido pelo Heavy Armor Master quando o PC está em
    # armadura pesada e o ataque é não-mágico.
    PHYSICAL_DAMAGE_TYPES = %w[contundente perfurante cortante bludgeoning piercing slashing].freeze

    # Sinônimos PT/EN aceitos como damage_type (case-insensitive).
    DAMAGE_TYPE_NORMALIZE = {
      'fogo' => 'fogo', 'fire' => 'fogo',
      'frio' => 'frio', 'cold' => 'frio',
      'ácido' => 'ácido', 'acido' => 'ácido', 'acid' => 'ácido',
      'relâmpago' => 'relâmpago', 'relampago' => 'relâmpago', 'lightning' => 'relâmpago', 'eletrico' => 'relâmpago', 'elétrico' => 'relâmpago',
      'trovão' => 'trovão', 'trovao' => 'trovão', 'thunder' => 'trovão',
      'veneno' => 'veneno', 'poison' => 'veneno',
      'necrótico' => 'necrótico', 'necrotico' => 'necrótico', 'necrotic' => 'necrótico',
      'radiante' => 'radiante', 'radiant' => 'radiante',
      'psíquico' => 'psíquico', 'psiquico' => 'psíquico', 'psychic' => 'psíquico',
      'energia' => 'energia', 'force' => 'energia',
      'contundente' => 'contundente', 'bludgeoning' => 'contundente', 'concussao' => 'contundente', 'concussão' => 'contundente',
      'perfurante' => 'perfurante', 'piercing' => 'perfurante',
      'cortante' => 'cortante', 'slashing' => 'cortante'
    }.freeze

    def normalize(raw)
      return nil if raw.nil?
      key = raw.to_s.strip.downcase
      DAMAGE_TYPE_NORMALIZE[key] || key
    end

    # Coleta o CONJUNTO COMPLETO de defesas do alvo (independente de tipo):
    # resistances / immunities / vulnerabilities + estado de armadura (HAM).
    # `force_summary`: quando true, UNE as defesas DERIVADAS do
    # CharacterSheetSummaryService (resistências de subclasse/itens + racial +
    # armadura pesada). O DamageService só força quando há `damage_type`; o
    # TypedDamageService força sempre (há várias parcelas/tipos).
    def collect_defenses(combatant, force_summary:)
      target = combatant.combatable

      if target.is_a?(CombatNpc)
        return {
          resistances:     Array(target.respond_to?(:resistances) ? target.resistances : []).map { |r| normalize(r) }.compact,
          immunities:      Array(target.respond_to?(:damage_immunities) ? target.damage_immunities : []).map { |r| normalize(r) }.compact,
          vulnerabilities: Array(target.respond_to?(:damage_vulnerabilities) ? target.damage_vulnerabilities : []).map { |r| normalize(r) }.compact,
          wearing_heavy_armor: false,
          feats: [],
          ham_flat_reduction: 0,
        }
      end

      meta_source =
        if target.respond_to?(:sheet) && target.sheet&.metadata.is_a?(Hash)
          target.sheet.metadata
        elsif target.respond_to?(:metadata) && target.metadata.is_a?(Hash)
          target.metadata
        else
          {}
        end

      mods = {
        resistances:     Array(meta_source['resistances']).map { |r| normalize(r) }.compact,
        immunities:      Array(meta_source['damage_immunities']).map { |r| normalize(r) }.compact,
        vulnerabilities: Array(meta_source['damage_vulnerabilities']).map { |r| normalize(r) }.compact,
        wearing_heavy_armor: !!meta_source['wearing_heavy_armor'],
        feats: Array(meta_source['feats']).select { |f| f.is_a?(Hash) },
        ham_flat_reduction: 0,
      }

      merge_summary_defenses!(mods, target) if force_summary
      mods
    end

    # Une ao `mods` as defesas derivadas + estado de armadura do PC vindos do
    # CharacterSheetSummaryService (fonte única). Best-effort: em erro, mantém
    # o que veio de `sheet.metadata`.
    def merge_summary_defenses!(mods, target)
      sheet = target.respond_to?(:sheet) ? target.sheet : nil
      return unless sheet&.id

      cmd = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
      return unless cmd&.success?

      summary = cmd.result || {}
      m = summary[:modifiers] || {}

      mods[:resistances]     |= Array(m[:resistances]).map { |r| normalize(r) }.compact
      mods[:immunities]      |= Array(m[:damage_immunities]).map { |r| normalize(r) }.compact
      mods[:vulnerabilities] |= Array(m[:damage_vulnerabilities]).map { |r| normalize(r) }.compact

      armor_cat = summary.dig(:equipment, :ac, :armor_category).to_s.downcase
      mods[:wearing_heavy_armor] ||= (armor_cat == 'heavy')

      mods[:ham_flat_reduction] = m[:damage_reduction_nonmagical_bps].to_i
    rescue StandardError => e
      Rails.logger.warn("DamageMitigationRules: enriquecimento via summary falhou: #{e.class}: #{e.message}") if defined?(Rails)
      nil
    end

    # :immune | :vulnerable | :resistant | :normal para o tipo dado.
    def decide_modifier(mods, damage_type)
      return :normal if damage_type.nil?
      return :immune     if mods[:immunities].include?(damage_type)
      return :vulnerable if mods[:vulnerabilities].include?(damage_type)
      return :resistant  if mods[:resistances].include?(damage_type)
      :normal
    end

    def apply_modifier(amount, modifier)
      case modifier
      when :immune     then 0
      when :resistant  then [amount / 2, 0].max
      when :vulnerable then amount * 2
      else                  amount
      end
    end

    # Redução fixa (HAM): -N dano físico não-mágico em armadura pesada, ANTES
    # da resistência (ordem PHB).
    def flat_reduction(mods, damage_type, magical)
      return 0 unless mods[:wearing_heavy_armor]
      return 0 if magical
      return 0 unless PHYSICAL_DAMAGE_TYPES.include?(damage_type.to_s)

      from_summary = mods[:ham_flat_reduction].to_i
      return from_summary if from_summary.positive?

      ham = mods[:feats].any? { |f| (f['feat_id'] || f[:feat_id]).to_s == 'maestria_em_armadura_pesada' }
      ham ? 3 : 0
    end

    # Mitiga UMA parcela: HAM (flat, antes) → modificador por tipo. Devolve o
    # dano final + o modificador aplicado + o tipo canônico (p/ o breakdown).
    def mitigate_parcel(amount, damage_type, magical, mods)
      dt = normalize(damage_type)
      after_flat = [amount.to_i - flat_reduction(mods, dt, magical), 0].max
      modifier = decide_modifier(mods, dt)
      { final: apply_modifier(after_flat, modifier), raw: amount.to_i, modifier: modifier, damage_type: dt }
    end
  end
end
