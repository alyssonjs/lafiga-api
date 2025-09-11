class FeatureGrantService
  prepend SimpleCommand

  # Grants class and subclass features when leveling from X to Y (inclusive of Y)
  # Params:
  # - sheet: Sheet
  # - klass: Klass
  # - from_level: Integer (previous class level)
  # - to_level: Integer (new class level)
  def initialize(sheet:, klass:, from_level:, to_level:)
    @sheet = sheet
    @klass = klass
    @from = from_level.to_i
    @to = to_level.to_i
  end

  def call
    return if @to <= @from
    character = @sheet.character
    sub_klass_id = @sheet.sheet_klasses.find_by(klass_id: @klass.id)&.sub_klass_id
    sub_klass = sub_klass_id ? SubKlass.find_by(id: sub_klass_id) : nil
    
    Rails.logger.info "FeatureGrantService: from_level=#{@from}, to_level=#{@to}, sub_klass_id=#{sub_klass_id}"

    ((@from + 1)..@to).each do |lvl|
      # Grant class-level features
      Rails.logger.info "Processing level #{lvl} features"
      if (cl = @klass.class_levels.includes(:features).find_by(level: lvl))
        Rails.logger.info "Found #{cl.features.count} class features for level #{lvl}"
        cl.features.each do |feat|
          grant(character, feat, source_type: 'Klass', source_id: @klass.id, gained_at_level: lvl)
        end
      else
        Rails.logger.info "No class features found for level #{lvl}"
      end
      # Grant subclass-level features if applicable
      if sub_klass
        skl = SubKlassLevel.includes(:features).find_by(sub_klass_id: sub_klass.id, level: lvl)
        if skl
          Rails.logger.info "Found #{skl.features.count} subclass features for level #{lvl}"
          skl.features.each do |feat|
            grant(character, feat, source_type: 'SubKlass', source_id: sub_klass.id, gained_at_level: lvl)
          end
        else
          Rails.logger.info "No subclass features found for level #{lvl}"
        end
      end
    end
    Rails.logger.info "FeatureGrantService completed successfully"
    true
  rescue => e
    Rails.logger.error "FeatureGrantService failed: #{e.message}"
    Rails.logger.error "FeatureGrantService backtrace: #{e.backtrace.join('\n')}"
    errors.add(:base, e.message)
    false
  end

  private

  def grant(character, feature, source_type:, source_id:, gained_at_level:)
    Rails.logger.info "Granting feature #{feature.name} (#{feature.id}) to character #{character.id} at level #{gained_at_level}"
    CharactersFeature.find_or_create_by!(character_id: character.id, feature_id: feature.id) do |cf|
      cf.source = source_type.downcase
      cf.level = gained_at_level # legacy column kept for compatibility
      cf.source_type = source_type
      cf.source_id = source_id
      cf.gained_at_level = gained_at_level
      cf.show = true
    end
  end
end
