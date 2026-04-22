# frozen_string_literal: true

module Subclasses
  # SyncFeaturesFromLevelsJsonService — popula `SubKlassLevel` + `Feature` a
  # partir do `SubKlass#levels_json` (que e a fonte de verdade vinda de
  # `config/subclass_overrides.yml` via `dnd:apply_subclass_overrides`).
  #
  # Bug de origem: ficha do Adimael (Patrulheiro/Batedor nv 9) nao mostrava
  # nenhuma feature de subclasse. Causa: `CharacterSheetSummaryService` lista
  # features lendo `SubKlass#sub_klass_levels.features`, mas para subclasses
  # que NAO vem da SRD (ex: Batedor/XGtE) ninguem populava esses registros.
  # `dnd:import` so popula SubKlassLevel para subs SRD; `subclasses:import`
  # so cria features placeholder para subs novas (skip se ja existe).
  #
  # Esse serviço e idempotente: cada feature recebe `api_index` prefixado pelo
  # api_index da subclasse para evitar colisoes de nome (ex: duas subs com
  # "Movimento Rápido" geram features distintas).
  #
  # Uso:
  #   Subclasses::SyncFeaturesFromLevelsJsonService.new(sub_klass).call
  #   Subclasses::SyncFeaturesFromLevelsJsonService.run_all
  class SyncFeaturesFromLevelsJsonService
    Result = Struct.new(
      :status, :sub_klass_id, :api_index, :levels_synced, :features_synced, :error,
      keyword_init: true
    )

    def self.run_all(update_descriptions: false, logger: nil)
      results = []
      SubKlass.find_each do |sub|
        results << new(sub, update_descriptions: update_descriptions).call
      rescue StandardError => e
        results << Result.new(
          status: :error, sub_klass_id: sub.id, api_index: sub.api_index, error: e.message,
        )
      end
      log_summary(results, logger) if logger
      results
    end

    def self.log_summary(results, logger)
      by_status = results.group_by(&:status).transform_values(&:size)
      logger.call(
        "[SubKlassLevelSync] total=#{results.size} " +
        by_status.map { |k, v| "#{k}=#{v}" }.join(' '),
      )
      results.each do |r|
        next unless r.status == :error || r.status == :synced
        logger.call(
          "  sub ##{r.sub_klass_id} (#{r.api_index}) #{r.status}: " \
          "levels=#{r.levels_synced} features=#{r.features_synced} #{r.error}",
        )
      end
    end

    def initialize(sub_klass, update_descriptions: false)
      @sub = sub_klass
      @update_descriptions = update_descriptions
    end

    def call
      rows = parse_levels_json
      return result(:skipped_empty) if rows.empty?

      levels_synced = 0
      features_synced = 0

      rows.each do |row|
        lvl = row['level'].to_i
        next unless lvl.between?(1, 20)

        level_record = @sub.sub_klass_levels.find_or_create_by!(level: lvl)
        levels_synced += 1

        Array(row['features']).each do |feat|
          feature = upsert_feature(feat)
          next unless feature

          unless level_record.features.exists?(feature.id)
            level_record.features << feature
          end
          features_synced += 1
        end
      end

      result(:synced, levels_synced: levels_synced, features_synced: features_synced)
    end

    private

    def parse_levels_json
      raw = @sub.levels_json.presence
      return [] if raw.blank?

      parsed = JSON.parse(raw) rescue []
      Array(parsed).select { |r| r.is_a?(Hash) && r['level'].to_i.positive? }
    end

    def upsert_feature(feat)
      return nil unless feat.is_a?(Hash)
      name = feat['name'].to_s.strip
      return nil if name.blank?

      api_index = build_feature_api_index(feat, name)
      record = Feature.find_or_initialize_by(api_index: api_index)
      record.name = name if record.name.blank? || @update_descriptions
      desc = feat['description'].to_s
      if desc.present? && (record.description.blank? || @update_descriptions)
        record.description = desc if record.respond_to?(:description=)
      end
      record.category = :subclass_feature if record.respond_to?(:category=)
      record.save!
      record
    end

    # Prefixa o api_index com o api_index da subklass para isolar features
    # com mesmo nome em subclasses diferentes. Se a feature ja vier com
    # `api_index` explicito no JSON, respeita.
    def build_feature_api_index(feat, name)
      raw = feat['api_index'] || feat['index']
      return raw.to_s if raw.present?
      slug = ActiveSupport::Inflector.transliterate(name).downcase
                                     .gsub(/[^a-z0-9]+/, '-')
                                     .gsub(/^-+|-+$/, '')
      "#{@sub.api_index}-#{slug}"
    end

    def result(status, **attrs)
      Result.new(
        status: status,
        sub_klass_id: @sub.id,
        api_index: @sub.api_index,
        levels_synced: 0,
        features_synced: 0,
        **attrs,
      )
    end
  end
end
