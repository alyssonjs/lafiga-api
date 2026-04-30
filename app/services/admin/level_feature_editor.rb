# frozen_string_literal: true

module Admin
  class LevelFeatureEditor
    Result = Struct.new(:level_record, :feature, keyword_init: true)

    def self.for_klass(klass, attrs, feature_id: nil)
      new(owner: klass, owner_kind: :klass, attrs: attrs, feature_id: feature_id).call
    end

    def self.for_sub_klass(sub_klass, attrs, feature_id: nil)
      new(owner: sub_klass, owner_kind: :sub_klass, attrs: attrs, feature_id: feature_id).call
    end

    def self.delete_for_klass(klass, feature_id, attrs = {})
      new(owner: klass, owner_kind: :klass, attrs: attrs, feature_id: feature_id).delete
    end

    def self.delete_for_sub_klass(sub_klass, feature_id, attrs = {})
      new(owner: sub_klass, owner_kind: :sub_klass, attrs: attrs, feature_id: feature_id).delete
    end

    def initialize(owner:, owner_kind:, attrs:, feature_id: nil)
      @owner = owner
      @owner_kind = owner_kind
      @attrs = attrs.to_h.stringify_keys
      @feature_id = feature_id
    end

    def call
      @feature_id.present? ? update_existing : create_new
    end

    def delete
      feature = scoped_feature!
      levels = levels_for_delete(feature).to_a
      raise ActiveRecord::RecordNotFound, 'Feature level not found' if levels.empty?

      ActiveRecord::Base.transaction do
        levels.each { |level| level.features.delete(feature) }
        destroy_orphan_custom_feature!(feature)
      end

      Result.new(level_record: levels.first, feature: feature)
    end

    private

    attr_reader :owner, :owner_kind, :attrs, :feature_id

    def create_new
      level = required_level!
      name = required_name!
      description = attrs['description'].to_s
      level_record = find_or_create_level!(level)

      feature = Feature.create!(
        api_index: attrs['api_index'].presence || unique_api_index(level, name),
        name: name,
        description: description,
        category: feature_category,
        dm_customized: true,
      )
      level_record.features << feature unless level_record.features.exists?(feature.id)

      Result.new(level_record: level_record, feature: feature)
    end

    def update_existing
      feature = scoped_feature!
      current_level_ids = current_levels_for(feature).pluck(:id)
      level_record = target_level_for_update(feature)
      moving_to_new_level = attrs.key?('level') && !current_level_ids.include?(level_record.id)

      ActiveRecord::Base.transaction do
        updates = {}
        updates[:name] = required_name! if attrs.key?('name')
        updates[:description] = attrs['description'].to_s if attrs.key?('description')
        updates[:category] = feature_category
        updates[:dm_customized] = true if feature.respond_to?(:dm_customized=)
        feature.update!(updates)

        if moving_to_new_level
          current_levels_for(feature).where.not(id: level_record.id).find_each do |row|
            row.features.delete(feature)
          end
        end
        level_record.features << feature unless level_record.features.exists?(feature.id)
      end

      Result.new(level_record: level_record, feature: feature.reload)
    end

    def target_level_for_update(feature)
      return find_or_create_level!(required_level!) if attrs.key?('level')

      current_levels_for(feature).first || raise(ActiveRecord::RecordNotFound, 'Feature level not found')
    end

    def levels_for_delete(feature)
      scope = current_levels_for(feature)
      return scope unless attrs.key?('level')

      scope.where(level: required_level!)
    end

    def destroy_orphan_custom_feature!(feature)
      return unless feature.respond_to?(:dm_customized?) && feature.dm_customized?
      return if feature.class_levels.exists?
      return if feature.sub_klass_levels.exists?
      return if defined?(CharactersFeature) && CharactersFeature.where(feature_id: feature.id).exists?

      feature.destroy!
    end

    def scoped_feature!
      scope = Feature.joins(level_association).merge(level_model.where(owner_foreign_key => owner.id)).distinct
      by_id = feature_id.to_s.match?(/\A\d+\z/) ? scope.find_by(id: feature_id) : nil
      by_id || scope.find_by(api_index: feature_id) ||
        raise(ActiveRecord::RecordNotFound, 'Feature not found for this class/subclass')
    end

    def current_levels_for(feature)
      feature.public_send(level_association).where(owner_foreign_key => owner.id)
    end

    def find_or_create_level!(level)
      if owner_kind == :klass
        owner.class_levels.find_or_create_by!(level: level) do |row|
          row.prof_bonus = proficiency_bonus_for(level)
          row.ability_score_bonuses = 0
        end
      else
        owner.sub_klass_levels.find_or_create_by!(level: level)
      end
    end

    def required_level!
      raw = attrs['level']
      level = raw.to_i
      raise ArgumentError, 'level deve estar entre 1 e 20' unless level.between?(1, 20)

      level
    end

    def required_name!
      name = attrs['name'].to_s.strip
      raise ArgumentError, 'name e obrigatorio' if name.blank?

      name
    end

    def unique_api_index(level, name)
      owner_slug = owner.api_index.presence || "#{owner_kind}-#{owner.id}"
      base = "#{owner_slug}-level-#{level}-#{parameterize(name)}"
      candidate = base
      suffix = 2
      while Feature.exists?(api_index: candidate)
        candidate = "#{base}-#{suffix}"
        suffix += 1
      end
      candidate
    end

    def parameterize(text)
      I18n.transliterate(text.to_s)
          .downcase
          .strip
          .gsub(/[^a-z0-9]+/, '-')
          .gsub(/^-+|-+$/, '')
          .presence || 'feature'
    end

    def proficiency_bonus_for(level)
      2 + ((level - 1) / 4)
    end

    def feature_category
      owner_kind == :klass ? :class_feature : :subclass_feature
    end

    def level_association
      owner_kind == :klass ? :class_levels : :sub_klass_levels
    end

    def level_model
      owner_kind == :klass ? ClassLevel : SubKlassLevel
    end

    def owner_foreign_key
      owner_kind == :klass ? :klass_id : :sub_klass_id
    end
  end
end
