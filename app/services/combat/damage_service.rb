module Combat
  # Aplica dano a um combatente respeitando resistência / imunidade /
  # vulnerabilidade e reduções fixas (Heavy Armor Master), e devolve
  # se um teste de concentração é necessário.
  #
  # Regras D&D 5e (PHB 5e p. 197):
  #   - Imune ao tipo de dano        → dano = 0
  #   - Resistente ao tipo de dano   → dano metade (round down, mínimo 0)
  #   - Vulnerável ao tipo de dano   → dano dobrado
  #   - Reduções fixas (HAM)         → subtraídas ANTES da divisão por
  #     resistência (PHB: "reduções primeiro, depois resistência").
  #
  # Concentração: ao tomar dano, combatente concentrando faz CON save com
  # CD = max(10, dano_aplicado / 2). Note que o cálculo usa o dano FINAL
  # (pós-modifiers), não o bruto — corrigido na Fase 6A.
  #
  # Fontes de modifiers:
  #   - PC (Character): `sheet.metadata['resistances'/...]` como OVERRIDE manual,
  #     UNIDO às defesas derivadas do `CharacterSheetSummaryService`
  #     (`summary[:modifiers][:resistances/damage_immunities/damage_vulnerabilities]`
  #     + `equipment.ac.armor_category` p/ `wearing_heavy_armor` +
  #     `damage_reduction_nonmagical_bps` p/ o HAM). O summary só é consultado
  #     quando há `damage_type` (sem tipo nenhuma mitigação se aplica).
  #   - NPC (CombatNpc): `combatable.resistances/immunities/vulnerabilities`
  #     (Fase 6E adiciona essas colunas; antes disso, vazio).
  class DamageService
    prepend SimpleCommand

    # Dano físico (B/P/S) reduzido pelo Heavy Armor Master quando o PC
    # está em armadura pesada e o ataque é não-mágico.
    PHYSICAL_DAMAGE_TYPES = %w[contundente perfurante cortante bludgeoning piercing slashing].freeze

    # Sinônimos PT/EN aceitos como damage_type (case-insensitive).
    DAMAGE_TYPE_NORMALIZE = {
      'fogo' => 'fogo', 'fire' => 'fogo',
      'frio' => 'frio', 'cold' => 'frio',
      'ácido' => 'ácido', 'acido' => 'ácido', 'acid' => 'ácido',
      'relâmpago' => 'relâmpago', 'relampago' => 'relâmpago', 'lightning' => 'relâmpago',
      'trovão' => 'trovão', 'trovao' => 'trovão', 'thunder' => 'trovão',
      'veneno' => 'veneno', 'poison' => 'veneno',
      'necrótico' => 'necrótico', 'necrotico' => 'necrótico', 'necrotic' => 'necrótico',
      'radiante' => 'radiante', 'radiant' => 'radiante',
      'psíquico' => 'psíquico', 'psiquico' => 'psíquico', 'psychic' => 'psíquico',
      'energia' => 'energia', 'force' => 'energia',
      'contundente' => 'contundente', 'bludgeoning' => 'contundente',
      'perfurante' => 'perfurante', 'piercing' => 'perfurante',
      'cortante' => 'cortante', 'slashing' => 'cortante'
    }.freeze

    def initialize(combatant:, amount:, current_user: nil, damage_type: nil, magical: false, attack_kind: 'normal')
      @combatant   = combatant
      @amount      = amount.to_i
      @current_user = current_user
      @damage_type = normalize_damage_type(damage_type)
      @magical     = !!magical
      # 'normal' | 'critical' — usado em PHB p. 197 para death saves de PCs
      # inconscientes (a 0 HP). Auto-hit a 5 ft (paralyzed/etc) usa 'critical'
      # também — o caller sinaliza via attack_kind.
      @attack_kind = attack_kind.to_s
    end

    def call
      return errors.add(:combatant, 'inexistente') && nil if @combatant.nil?
      return errors.add(:amount, 'deve ser >= 0') && nil if @amount.negative?

      was_concentrating = @combatant.is_concentrating

      modifiers = collect_target_modifiers
      damage_modifier = decide_damage_modifier(modifiers)
      flat_reduction  = compute_flat_reduction(modifiers)

      raw = @amount
      after_flat = [raw - flat_reduction, 0].max

      final = apply_damage_modifier(after_flat, damage_modifier)

      # PHB p. 197 — Ataque contra PC inconsciente (a 0 HP):
      # cada acerto adiciona 1 falha de death save; crítico adiciona 2.
      # Aplica-se ANTES do `apply_damage!` porque o estado relevante é
      # "alvo a 0 HP no momento do ataque". `is_dead` (NPC) ou já-morto
      # (3 falhas anteriores) não dispara mais.
      death_save_failures_added = compute_death_save_failures_from_attack
      death_save_failures_added.times { @combatant.record_death_save!(:failure) }

      @combatant.apply_damage!(final)

      {
        combatant: @combatant,
        damage_applied: final,
        damage_raw: raw,
        damage_type: @damage_type,
        damage_modifier: damage_modifier,            # :immune | :resistant | :vulnerable | :normal
        flat_reduction_applied: flat_reduction,
        attack_kind: @attack_kind,
        death_save_failures_added: death_save_failures_added,
        concentration_check_required: was_concentrating && final.positive? && !@combatant.is_dead,
        concentration_dc: was_concentrating && final.positive? ? [10, final / 2].max : nil,
      }
    rescue ArgumentError => e
      errors.add(:base, e.message)
      nil
    end

    private

    def normalize_damage_type(raw)
      return nil if raw.nil?
      key = raw.to_s.strip.downcase
      DAMAGE_TYPE_NORMALIZE[key] || key
    end

    # Lê resistances / damage_immunities / damage_vulnerabilities do alvo.
    # Para PC (Character): `sheet.metadata['resistances'/'damage_immunities'/...]`
    # e flag `wearing_heavy_armor` para HAM.
    # Para NPC (CombatNpc): colunas dedicadas adicionadas na Fase 6E.
    def collect_target_modifiers
      target = @combatant.combatable

      # Caminho NPC — colunas dedicadas (Fase 6E)
      if target.is_a?(CombatNpc)
        return {
          resistances: Array(target.respond_to?(:resistances) ? target.resistances : [])
                        .map { |r| normalize_damage_type(r) }.compact,
          immunities: Array(target.respond_to?(:damage_immunities) ? target.damage_immunities : [])
                        .map { |r| normalize_damage_type(r) }.compact,
          vulnerabilities: Array(target.respond_to?(:damage_vulnerabilities) ? target.damage_vulnerabilities : [])
                        .map { |r| normalize_damage_type(r) }.compact,
          wearing_heavy_armor: false,  # NPCs não têm a flag específica do feat
          feats: []
        }
      end

      # Caminho PC — sheet.metadata
      meta_source =
        if target.respond_to?(:sheet) && target.sheet&.metadata.is_a?(Hash)
          target.sheet.metadata
        elsif target.respond_to?(:metadata) && target.metadata.is_a?(Hash)
          target.metadata
        else
          {}
        end

      mods = {
        resistances: Array(meta_source['resistances']).map { |r| normalize_damage_type(r) }.compact,
        immunities:  Array(meta_source['damage_immunities']).map { |r| normalize_damage_type(r) }.compact,
        vulnerabilities: Array(meta_source['damage_vulnerabilities']).map { |r| normalize_damage_type(r) }.compact,
        wearing_heavy_armor: !!meta_source['wearing_heavy_armor'],
        feats: Array(meta_source['feats']).select { |f| f.is_a?(Hash) },
        ham_flat_reduction: 0,
      }

      # Enriquecimento via summary — fonte única das defesas DERIVADAS de um PC
      # (resistências/imunidades de subclasse + itens equipados) e do estado de
      # ARMADURA (para o HAM). O `sheet.metadata` sozinho não materializa isso em
      # prod (só `metadata['feats']` é backfilled), então sem este passo o
      # DamageService nunca vê resistência de subclasse nem armadura pesada.
      #
      # Guard: só consultamos o summary quando HÁ `damage_type`. Sem tipo,
      # `decide_damage_modifier` → :normal e `compute_flat_reduction` → 0 (nil
      # não é físico), ou seja nenhuma mitigação se aplica — evitamos o custo do
      # summary no caminho comum (todos os callers atuais chamam SEM tipo).
      merge_summary_modifiers!(mods, target) if @damage_type.present?

      mods
    end

    # Une ao `mods` as defesas derivadas + estado de armadura do PC vindos do
    # CharacterSheetSummaryService. Best-effort: em qualquer erro, mantém apenas
    # o que veio de `sheet.metadata` (override/fallback conservador).
    #
    # - resistances/immunities/vulnerabilities: UNIÃO (metadata ∪ summary), pois
    #   ambos são válidos (metadata = override manual do Mestre; summary = regra).
    # - wearing_heavy_armor: metadata OU (armor_category == 'heavy').
    # - ham_flat_reduction: valor de `damage_reduction_nonmagical_bps` (encapsula
    #   presença do feat + valor 3). Usado com prioridade em compute_flat_reduction.
    def merge_summary_modifiers!(mods, target)
      sheet = target.respond_to?(:sheet) ? target.sheet : nil
      return unless sheet&.id

      cmd = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
      return unless cmd&.success?

      summary = cmd.result || {}
      m = summary[:modifiers] || {}

      mods[:resistances]     |= Array(m[:resistances]).map { |r| normalize_damage_type(r) }.compact
      mods[:immunities]      |= Array(m[:damage_immunities]).map { |r| normalize_damage_type(r) }.compact
      mods[:vulnerabilities] |= Array(m[:damage_vulnerabilities]).map { |r| normalize_damage_type(r) }.compact

      armor_cat = summary.dig(:equipment, :ac, :armor_category).to_s.downcase
      mods[:wearing_heavy_armor] ||= (armor_cat == 'heavy')

      mods[:ham_flat_reduction] = m[:damage_reduction_nonmagical_bps].to_i
    rescue StandardError => e
      Rails.logger.warn("DamageService: enriquecimento via summary falhou: #{e.class}: #{e.message}") if defined?(Rails)
      nil
    end

    def decide_damage_modifier(mods)
      return :normal if @damage_type.nil?

      return :immune     if mods[:immunities].include?(@damage_type)
      return :vulnerable if mods[:vulnerabilities].include?(@damage_type)
      return :resistant  if mods[:resistances].include?(@damage_type)
      :normal
    end

    def apply_damage_modifier(amount, modifier)
      case modifier
      when :immune     then 0
      when :resistant  then [amount / 2, 0].max
      when :vulnerable then amount * 2
      else                  amount
      end
    end

    # Reduções fixas (HAM): subtraídas ANTES da resistência (PHB ordem).
    # Heavy Armor Master: -3 dano físico não-mágico em armadura pesada.
    def compute_flat_reduction(mods)
      return 0 unless mods[:wearing_heavy_armor]
      return 0 if @magical
      return 0 unless PHYSICAL_DAMAGE_TYPES.include?(@damage_type.to_s)

      # Preferir o valor derivado do summary (encapsula presença do feat + valor).
      # Fallback: detecção do feat direto em metadata['feats'] (compat com specs
      # e com fichas cujo summary não pôde ser construído).
      from_summary = mods[:ham_flat_reduction].to_i
      return from_summary if from_summary.positive?

      ham = mods[:feats].any? { |f| (f['feat_id'] || f[:feat_id]).to_s == 'maestria_em_armadura_pesada' }
      ham ? 3 : 0
    end

    # PHB p. 197 — alvo PC com 0 HP atingido por ataque sofre 1 falha de
    # death save (acerto normal) ou 2 falhas (acerto crítico). NPCs morrem
    # diretamente a 0 HP (não usam death saves), então o caso só aplica a
    # combatable_type == Character.
    def compute_death_save_failures_from_attack
      return 0 unless @combatant.combatable_type == 'Character'
      return 0 unless @combatant.hp_current.to_i == 0
      return 0 if @combatant.is_dead

      @attack_kind == 'critical' ? 2 : 1
    end
  end
end
