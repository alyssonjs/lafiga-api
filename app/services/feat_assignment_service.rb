class FeatAssignmentService
  prepend SimpleCommand

  def initialize(sheet:, feat_id:, level_gained:, choices: {})
    @sheet = sheet
    @feat_id = feat_id
    @level_gained = level_gained
    @choices = choices.is_a?(ActionController::Parameters) ? choices.to_unsafe_h : (choices || {})
  end

  def call
    ActiveRecord::Base.transaction do
      Rails.logger.info "=== FeatAssignmentService Debug ==="
      Rails.logger.info "feat_id: #{@feat_id}"
      Rails.logger.info "choices: #{@choices.inspect}"
      Rails.logger.info "sheet_id: #{@sheet.id}"
      
      # Check if feat exists in rules
      feat_rule = FeatRules.find(@feat_id)
      unless feat_rule
        Rails.logger.error "Feat não encontrado: #{@feat_id}"
        errors.add(:feat, 'não encontrado')
        return nil
      end
      Rails.logger.info "Feat encontrado: #{feat_rule[:name]}"

      # Check prerequisites
      unless FeatRules.check_prerequisites(@feat_id, @sheet)
        Rails.logger.error "Pré-requisitos não atendidos para feat: #{@feat_id}"
        errors.add(:feat, 'pré-requisitos não atendidos')
        return nil
      end
      Rails.logger.info "Pré-requisitos atendidos"

      # Check if sheet already has this feat
      if @sheet.sheet_feats.exists?(feat_id: @feat_id)
        Rails.logger.error "Sheet já possui este feat: #{@feat_id}"
        errors.add(:feat, 'já possui este talento')
        return nil
      end
      Rails.logger.info "Feat não duplicado"

      # Create or find feat in database
      feat = Feat.find_or_create_by(api_index: @feat_id) do |f|
        f.name = feat_rule[:name]
        f.description = feat_rule[:description]
        f.prerequisites = feat_rule[:prerequisites].to_json
        f.ability_bonuses = feat_rule[:ability_bonuses].to_json
        f.proficiency_bonuses = feat_rule[:proficiency_bonuses].to_json
        f.features = feat_rule[:features].to_json
      end

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

      sheet_feat
    end
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
    feats = metadata['feats'] || []
    
    feat_summary = FeatRules.apply(@feat_id, @choices)
    Rails.logger.info "feat_summary: #{feat_summary.inspect}"
    
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
      choices: @choices
    }

    metadata['feats'] = feats
    Rails.logger.info "Updating sheet metadata with feats: #{feats.inspect}"
    @sheet.update!(metadata: metadata)
    Rails.logger.info "Sheet metadata updated successfully"
  end

  def apply_feat_spells(sheet_feat)
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
end
