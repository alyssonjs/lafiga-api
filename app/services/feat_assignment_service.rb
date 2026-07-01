class FeatAssignmentService
  prepend SimpleCommand

  def initialize(sheet:, feat_id:, level_gained:, choices: {})
    @sheet = sheet
    # D1 — normaliza featId. FeatRules.find espera SLUG (api_index). Um cliente
    # que enviar o DB id numérico (ex.: Humano Variante por outro fluxo) caía em
    # "feat não encontrado". Resolvemos o slug a partir do Feat persistido.
    @feat_id = normalize_feat_id(feat_id)
    @level_gained = level_gained
    @choices = choices.is_a?(ActionController::Parameters) ? choices.to_unsafe_h : (choices || {})
  end

  # Numérico (DB id) → api_index do Feat; slug → inalterado; nil → nil.
  def normalize_feat_id(raw)
    s = raw.to_s.strip
    return raw if s.empty?
    return s unless s.match?(/\A\d+\z/)

    (Feat.find_by(id: s.to_i)&.api_index).presence || s
  end

  def call
    Rails.logger.info "=== FeatAssignmentService Debug ==="
    Rails.logger.info "feat_id: #{@feat_id}"
    Rails.logger.info "choices: #{@choices.inspect}"
    Rails.logger.info "sheet_id: #{@sheet.id}"

    # Validation failures must happen outside the DB transaction. Returning from
    # inside a nested transaction can poison the outer provisioning transaction
    # on PostgreSQL, surfacing later as PG::InFailedSqlTransaction.
    feat_rule = FeatRules.find(@feat_id)
    unless feat_rule
      Rails.logger.error "Feat não encontrado: #{@feat_id}"
      errors.add(:feat, 'não encontrado')
      return nil
    end
    Rails.logger.info "Feat encontrado: #{feat_rule[:name]}"

    unless FeatRules.check_prerequisites(@feat_id, @sheet)
      Rails.logger.error "Pré-requisitos não atendidos para feat: #{@feat_id}"
      errors.add(:feat, 'pré-requisitos não atendidos')
      return nil
    end
    Rails.logger.info "Pré-requisitos atendidos"

    sheet_feat = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      feat = Feat.find_or_create_by(api_index: @feat_id) do |f|
        f.name = feat_rule[:name]
        f.description = feat_rule[:description]
        f.prerequisites = feat_rule[:prerequisites].to_json
        f.ability_bonuses = feat_rule[:ability_bonuses].to_json
        f.proficiency_bonuses = feat_rule[:proficiency_bonuses].to_json
        f.features = feat_rule[:features].to_json
      end

      # Substituir talento no mesmo nível (ex.: edição de ASI no nível 4): remove DB + entrada em metadata.
      lg = @level_gained.to_i
      if lg.positive?
        SheetFeatLevelCleaner.call(sheet: @sheet, levels: [lg])
      end

      # Duplicação só é bloqueada quando o talento NÃO é repeatable. PHB
      # marca alguns como múltiplos (Adepto Elemental, Mágico Iniciante);
      # campanha Lafiga estende para Adepto Marcial, Poliglota, Perito,
      # Conjurador de Ritual (cumulativos por pick). Cobertura BDD em
      # `spec/services/feat_assignment_service_repeatable_spec.rb`.
      #
      # Quando repeatable=true e já existe ESSE feat no mesmo level_gained
      # (cenário improvável — só edição rápida), o `SheetFeatLevelCleaner`
      # acima já removeu a entrada antiga deste level, então `create!`
      # abaixo nao quebra a unique constraint (sheet_id, feat_id) — ver
      # migration 20260513* que relaxa a constraint pra (sheet_id, feat_id,
      # level_gained).
      is_repeatable = !!feat_rule[:repeatable]
      if !is_repeatable && @sheet.sheet_feats.exists?(feat: feat)
        Rails.logger.error "Sheet já possui este feat: #{@feat_id}"
        errors.add(:feat, 'já possui este talento')
        raise ActiveRecord::Rollback
      end
      Rails.logger.info "Feat não duplicado (repeatable=#{is_repeatable})"

      # Create sheet_feat association
      sheet_feat = @sheet.sheet_feats.create!(
        feat: feat,
        level_gained: @level_gained,
        choices: @choices.to_json
      )

      # Update sheet metadata with feat information
      update_sheet_metadata(sheet_feat)

      # Apply cantrips and spells if any. F7: além de `cantrips:`/`spells:`,
      # também rodamos quando a magia vive em special_rules.magic_modifiers
      # (Sniper Mágico learn_cantrip, Conjurador de Ritual ritual_book).
      apply_feat_spells(sheet_feat) if feat_rule[:cantrips] || feat_rule[:spells] || feat_has_spell_special_rules?(feat_rule)

      # Apply special rules if any. Para Robusto (`hit_points_bonus`) o caminho
      # `handle_immediate_special_rules` JÁ aplica +N×nível retroativamente em
      # sheet.hp_max — não precisa duplicar aqui. Cobertura: spec/services/feat_hp_bonus_spec.rb.
      apply_special_rules(sheet_feat) if feat_rule[:special_rules]

      # F5 — half-feats (Durável, Resiliente, Atleta, Proteção*, Sentinela, etc.)
      # gravam o +1/+2 apenas em metadata['feats'][].ability_bonuses. Em fichas
      # AUTORITATIVAS (colunas str..cha como fonte de verdade — criadas pelo
      # front/provisioning), o summary reconcilia com uma linha "Ajuste manual -1"
      # que cancela o bônus (net 0) porque as colunas não foram atualizadas.
      # `level_up_service`/`provisioning` já chamam o sync, mas o FeatAssignmentService
      # isolado (admin/API) não — então materializamos aqui.
      #
      # Restrito a fichas já autoritativas: fichas legadas (sem flag/base) já
      # mostram o bônus via `base + inc_total` e NÃO devem ser flipadas para o
      # modo autoritativo aqui (evita duplicar incrementos sem `base_ability_scores`).
      if feat_grants_ability_score?(feat_rule) && sheet_uses_authoritative_scores?(@sheet)
        CharacterSheetSummaryService.sync_ability_columns_from_metadata!(@sheet)
        @sheet.reload
      end
    end
    sheet_feat
  rescue StandardError => e
    errors.add(:base, e.message)
    nil
  end

  private

  # True quando o feat concede bônus de atributo (half-feat fixo `{con:1}` ou
  # com escolha `{choose:{...}}`). Usado para decidir se materializamos as
  # colunas autoritativas via sync (F5).
  def feat_grants_ability_score?(feat_rule)
    ab = feat_rule && (feat_rule[:ability_bonuses] || feat_rule['ability_bonuses'])
    ab = FeatRules.parse_jsonish(ab) if ab.is_a?(String)
    ab.is_a?(Hash) && ab.present?
  end

  # A ficha já trata as colunas str..cha como fonte autoritativa? (flag setada
  # pelo provisioning/level-up, OU `base_ability_scores` presente). Só nesse caso
  # o artefato "Ajuste manual -1" aparece e precisamos sincronizar as colunas (F5).
  def sheet_uses_authoritative_scores?(sheet)
    meta = sheet.metadata || {}
    return true if meta['ability_scores_include_all_increments']
    base = meta['base_ability_scores']
    base.is_a?(Hash) && base.keys.any?
  end

  def update_sheet_metadata(sheet_feat)
    Rails.logger.info "=== update_sheet_metadata Debug ==="
    Rails.logger.info "feat_id: #{@feat_id}"
    Rails.logger.info "choices: #{@choices.inspect}"
    
    metadata = @sheet.metadata || {}
    feats = Array(metadata['feats']).reject do |entry|
      next false unless entry.is_a?(Hash)
      egl = entry['level_gained'] || entry[:level_gained]
      egl.to_i == @level_gained.to_i
    end
    
    # IMPORTANTE: nao envolver em rescue silencioso. Antes, este bloco usava
    # um fallback que zerava `ability_bonuses`/`proficiency_bonuses` quando
    # `FeatRules.apply` lancava — exatamente o caminho que mascarou o bug do
    # Observador (Hash#inspect string em coluna text -> TypeError -> bonuses
    # zerados em metadata['feats'], ficha mostrava +0 em SAB). Agora o
    # `FeatRules.parse_jsonish` cura o caso de String corrompida, entao se
    # algo aqui ainda lancar, e bug REAL e deve subir para o transaction
    # rollback no `call` (rescue de toplevel ja captura e adiciona em errors).
    feat_summary = FeatRules.apply(@feat_id, @choices)
    Rails.logger.info "feat_summary: #{feat_summary.inspect}"
    
    # Apply special rules
    special_rules = {}
    feat_rule = FeatRules.find(@feat_id)
    if feat_rule&.dig(:special_rules)
      special_rules_service = FeatSpecialRulesService.new(@sheet, @feat_id, @choices)
      special_rules = special_rules_service.apply_special_rules
    end

    feats << {
      id: sheet_feat.id,
      feat_id: @feat_id,
      name: feat_summary[:name],
      level_gained: @level_gained,
      ability_bonuses: feat_summary[:ability_bonuses],
      proficiency_bonuses: feat_summary[:proficiency_bonuses],
      cantrips: feat_summary[:cantrips],
      spells: feat_summary[:spells],
      features: feat_summary[:features],
      choices: @choices,
      special_rules: special_rules
    }

    metadata['feats'] = feats
    Rails.logger.info "Updating sheet metadata with feats: #{feats.inspect}"
    @sheet.update!(metadata: metadata)
    Rails.logger.info "Sheet metadata updated successfully"
  end

  def apply_feat_spells(sheet_feat)
    # Sem rescue silencioso (ver comentario em update_sheet_metadata): se
    # FeatRules.apply lancar, deixa subir para o rescue de toplevel do call.
    feat_summary = FeatRules.apply(@feat_id, @choices)
    feat_rule    = FeatRules.find(@feat_id)

    # F8 — acesso INDIFERENTE a símbolo/string. `FeatRules.apply` monta o
    # sub-hash com chave STRING (`{ 'cantrips' => [...] }`); ler por símbolo
    # (`feat_summary[:cantrips][:cantrips]`) devolvia nil e NENHUM
    # SheetKnownSpell era criado (Mágico Iniciante: 0 magias).
    cantrip_tokens = extract_spell_tokens(feat_summary[:cantrips], 'cantrips')
    spell_tokens   = extract_spell_tokens(feat_summary[:spells], 'spells')

    # F7 — magias de feat que vivem em special_rules.magic_modifiers (não em
    # `cantrips:`/`spells:`). Sniper Mágico (learn_cantrip → choices.cantrips) e
    # Conjurador de Ritual (ritual_book → choices.spells). Sem isto, o pick da
    # criação era descartado e nada virava SheetKnownSpell.
    mm = feat_spell_special_rules(feat_rule)
    if mm['learn_cantrip']
      cantrip_tokens |= Array(@choices['cantrips'] || @choices[:cantrips]).map(&:to_s)
    end
    if mm['ritual_book']
      spell_tokens |= Array(@choices['spells'] || @choices[:spells]).map(&:to_s)
    end

    sheet_klass = @sheet.sheet_klasses.first
    return unless sheet_klass

    # Mágico Iniciante: a magia de 1º nível é 1/descanso longo, SEM slot.
    one_per_long_rest = @feat_id.to_s == 'magico_iniciante'

    # O índice único é [sheet_klass_id, spell_id] (SEM source). Buscamos por essa
    # chave e só setamos source no INSERT — assim, se a magia já é conhecida (via
    # classe), não tentamos um segundo INSERT que violaria a unique e quebraria
    # todo o assignment (RecordNotUnique → rollback → 0 magias).
    cantrip_tokens.each do |token|
      cantrip = find_feat_spell(token, level: 0)
      next unless cantrip
      SheetKnownSpell.find_or_create_by(sheet_klass: sheet_klass, spell: cantrip) { |row| row.source = 'feat' }
    end

    spell_tokens.each do |token|
      spell = find_feat_spell(token)
      next unless spell
      sks = SheetKnownSpell.find_or_create_by(sheet_klass: sheet_klass, spell: spell) { |row| row.source = 'feat' }
      # 'LR' = 1/descanso longo (vocabulário do model SheetKnownSpell, que valida
      # uses_per_rest ∈ {LR, SR}). A magia de 1º nível do Mágico Iniciante não usa slot.
      if one_per_long_rest && sks.source == 'feat' && sks.uses_per_rest.blank?
        sks.update(uses_per_rest: 'LR', uses_remaining: 1)
      end
    end
  end

  # Extrai a lista de tokens (nomes OU ids) de um sub-hash {cantrips:[...]} /
  # {spells:[...]} aceitando chave símbolo ou string (F8).
  def extract_spell_tokens(block, key)
    return [] unless block.is_a?(Hash)
    Array(block[key] || block[key.to_sym]).map(&:to_s).reject(&:blank?)
  end

  # Resolve um token de magia (nome do catálogo PT, api_index/slug do front, ou
  # id numérico) para um Spell, de forma tolerante. O front grava IDs/slugs em
  # `choices.cantrips/spells`; a verificação in-transaction usa nomes.
  def find_feat_spell(token, level: nil)
    t = token.to_s.strip
    return nil if t.empty?
    scope = level ? Spell.where(level: level) : Spell.all
    scope.find_by(name: t) ||
      scope.find_by(api_index: t) ||
      scope.where('LOWER(name) = ?', t.downcase).first ||
      (t.match?(/\A\d+\z/) ? scope.find_by(id: t.to_i) : nil)
  end

  # Bloco magic_modifiers do feat (HashWithIndifferentAccess-friendly).
  def feat_spell_special_rules(feat_rule)
    sr = feat_rule && (feat_rule[:special_rules] || feat_rule['special_rules'])
    sr = FeatRules.parse_jsonish(sr) if sr.is_a?(String)
    return {} unless sr.is_a?(Hash)
    mm = sr[:magic_modifiers] || sr['magic_modifiers'] || {}
    mm.is_a?(Hash) ? mm.deep_stringify_keys : {}
  end

  def feat_has_spell_special_rules?(feat_rule)
    mm = feat_spell_special_rules(feat_rule)
    mm.key?('learn_cantrip') || mm.key?('ritual_book')
  end

  def apply_special_rules(sheet_feat)
    Rails.logger.info "=== apply_special_rules Debug ==="
    Rails.logger.info "feat_id: #{@feat_id}"
    Rails.logger.info "choices: #{@choices.inspect}"
    
    # Apply special rules using the service
    special_rules_service = FeatSpecialRulesService.new(@sheet, @feat_id, @choices)
    special_rules = special_rules_service.apply_special_rules
    
    Rails.logger.info "Applied special rules: #{special_rules.inspect}"
    
    # Handle specific special rules that need immediate application
    handle_immediate_special_rules(special_rules)
  end

  def handle_immediate_special_rules(special_rules)
    # Handle hit points bonus (retroactive). `special_rules` é o retorno fresh
    # de `apply_special_rules` (chaves simbolo). hp vive em `hp_max`/`hp_current`
    # — `hit_points` não existe na tabela `sheets` (ver schema.rb:427-429).
    hp_per_level_cfg = special_rules.dig(:dice, :hit_points_per_level) ||
                        special_rules.dig('dice', 'hit_points_per_level')
    if hp_per_level_cfg
      bonus_per_level = (hp_per_level_cfg[:bonus_per_level] || hp_per_level_cfg['bonus_per_level']).to_i
      retroactive     = hp_per_level_cfg[:retroactive] != false && hp_per_level_cfg['retroactive'] != false
      current_level   = @sheet.sheet_klasses.sum(:level).to_i
      total_bonus     = retroactive ? current_level * bonus_per_level : bonus_per_level

      if total_bonus.positive?
        was_at_full = @sheet.hp_current.to_i >= @sheet.hp_max.to_i
        new_max     = @sheet.hp_max.to_i + total_bonus
        new_current = was_at_full ? new_max : (@sheet.hp_current.to_i + total_bonus)
        @sheet.update!(hp_max: new_max, hp_current: new_current)
        Rails.logger.info "Applied retroactive HP bonus: +#{total_bonus} HP (max #{@sheet.hp_max - total_bonus} -> #{new_max})"
      end
    end

    # Handle luck points
    luck_cfg = special_rules.dig(:dice, :luck_points) || special_rules.dig('dice', 'luck_points')
    if luck_cfg
      metadata = @sheet.metadata || {}
      metadata['luck_points'] = luck_cfg[:points] || luck_cfg['points']
      @sheet.update!(metadata: metadata)
      Rails.logger.info "Initialized luck points: #{metadata['luck_points']}"
    end
  end
end
