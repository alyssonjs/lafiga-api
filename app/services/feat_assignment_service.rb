class FeatAssignmentService
  prepend SimpleCommand

  def initialize(sheet:, feat_id:, level_gained:, choices: {})
    @sheet = sheet
    @feat_id = feat_id
    @level_gained = level_gained
    @choices = choices.is_a?(ActionController::Parameters) ? choices.to_unsafe_h : (choices || {})
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

      # Apply cantrips and spells if any
      apply_feat_spells(sheet_feat) if feat_rule[:cantrips] || feat_rule[:spells]

      # Apply special rules if any. Para Robusto (`hit_points_bonus`) o caminho
      # `handle_immediate_special_rules` JÁ aplica +N×nível retroativamente em
      # sheet.hp_max — não precisa duplicar aqui. Cobertura: spec/services/feat_hp_bonus_spec.rb.
      apply_special_rules(sheet_feat) if feat_rule[:special_rules]
    end
    sheet_feat
  rescue StandardError => e
    errors.add(:base, e.message)
    nil
  end

  private

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
    
    # Apply cantrips
    if feat_summary[:cantrips] && feat_summary[:cantrips][:cantrips]
      cantrips = feat_summary[:cantrips][:cantrips]
      cantrips.each do |cantrip_name|
        # Find or create cantrip spell
        cantrip = Spell.find_by(name: cantrip_name, level: 0)
        if cantrip
          # Add to sheet's known cantrips
          sheet_klass = @sheet.sheet_klasses.first
          if sheet_klass
            SheetKnownSpell.find_or_create_by(
              sheet_klass: sheet_klass,
              spell: cantrip,
              source: 'feat'
            )
          end
        end
      end
    end

    # Apply spells
    if feat_summary[:spells] && feat_summary[:spells][:spells]
      spells = feat_summary[:spells][:spells]
      spells.each do |spell_name|
        # Find or create spell
        spell = Spell.find_by(name: spell_name)
        if spell
          # Add to sheet's known spells
          sheet_klass = @sheet.sheet_klasses.first
          if sheet_klass
            SheetKnownSpell.find_or_create_by(
              sheet_klass: sheet_klass,
              spell: spell,
              source: 'feat'
            )
          end
        end
      end
    end
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
