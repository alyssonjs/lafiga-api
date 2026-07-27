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
          feature = resolve_feature(feat, level_record)
          next unless feature

          unless level_record.features.exists?(feature.id)
            level_record.features << feature
          end
          features_synced += 1
        end

        # Dedup: colapsa features de MESMO nome no nível (mantém a de descrição
        # mais longa — tipicamente a canônica/editada pelo compêndio — e remove a
        # condensada duplicada gerada por re-imports com api_index divergente).
        dedup_same_name_features!(level_record)

        # Pruning (evita recorrência de ghosts/legados em re-import): após anexar
        # as canônicas deste nível, desassocia features de subclasse que NÃO casam
        # com nenhum nome canônico do levels_json — mas SÓ quando há canônica
        # presente E a remoção não esvazia o nível (mesmo critério seguro do
        # rake dnd:cleanup_sheet_data D1). Sem critério seguro → não remove.
        prune_orphan_features!(level_record, row)
      end

      result(:synced, levels_synced: levels_synced, features_synced: features_synced)
    end

    private

    # Resolve a Feature canônica de um `feat` do levels_json.
    # PREFERE reusar uma feature de MESMO nome já anexada ao nível (que pode ter
    # sido editada no compêndio e ter api_index legado/SRD, ex.: 'dark-ones-blessing'),
    # preservando a descrição do usuário. Só se não houver, cria/acha por api_index
    # canônico (`{sub}-{slug}`), evitando duplicatas.
    def resolve_feature(feat, level_record)
      return nil unless feat.is_a?(Hash)
      name = feat['name'].to_s.strip
      return nil if name.blank?

      norm = normalize_name(name)
      existing = level_record.features.to_a.find { |f| normalize_name(f.name) == norm }
      if existing
        # update_descriptions:false → só preenche descrição VAZIA; nunca sobrescreve
        # uma edição do compêndio.
        desc = feat['description'].to_s
        if desc.present? && existing.respond_to?(:description=) &&
           (existing.description.blank? || @update_descriptions)
          existing.update!(description: desc)
        end
        return existing
      end

      upsert_feature(feat)
    end

    # Colapsa features de MESMO nome (normalizado) no nível: mantém a de descrição
    # mais longa (tie → menor id/mais antiga) e desassocia as demais. Repontar as
    # associações de personagem para a mantida antes de remover, evitando perder o
    # vínculo em fichas existentes.
    def dedup_same_name_features!(level_record)
      groups = level_record.features.to_a.group_by { |f| normalize_name(f.name) }
      groups.each_value do |group|
        next if group.size <= 1
        # Preferir MANTER a edição do compêndio (dm_customized) — é a versão
        # autoritativa do mestre, mesmo que mais curta — depois a mais longa.
        keep = group.max_by { |f| [dm_customized?(f) ? 1 : 0, f.description.to_s.length, -f.id] }
        (group - [keep]).each do |f|
          if defined?(CharactersFeature)
            CharactersFeature.where(feature_id: f.id)
                             .where.not(character_id: CharactersFeature.where(feature_id: keep.id).select(:character_id))
                             .update_all(feature_id: keep.id)
            CharactersFeature.where(feature_id: f.id).delete_all
          end
          level_record.features.delete(f)
          f.reload
          # NUNCA destrói uma edição do compêndio — desassocia e mantém como backup
          # recuperável; só apaga de fato stubs gerados pelo sistema.
          f.destroy! if !dm_customized?(f) && !f.class_levels.exists? && !f.sub_klass_levels.exists?
        rescue ActiveRecord::InvalidForeignKey
          # mantém a Feature se ainda referenciada; a associação já foi removida.
        end
      end
    end

    # Remove (desassocia) features de subclasse do nível que não estão no
    # levels_json. Conservador: exige ≥1 canônica casada e nunca remove mais
    # do que o nº de canônicas (1:1 ou menos) para não esvaziar o nível.
    def prune_orphan_features!(level_record, row)
      canon_names = Array(row['features']).map { |f| normalize_name(f['name'] || f[:name]) }
                                          .reject(&:blank?)
      return if canon_names.empty?

      feats    = level_record.features.to_a
      matched  = feats.select { |f| canon_names.include?(normalize_name(f.name)) }
      nonmatch = feats.reject { |f| canon_names.include?(normalize_name(f.name)) }
      # CAUSA-RAIZ da perda de descrições/tabelas: quando o YAML RENOMEIA uma
      # feature, a versão editada pelo mestre (nome antigo) deixa de casar com o
      # canônico e o prune a DESTRUÍA. Edição do compêndio (dm_customized) é
      # sagrada — nunca podar. Fica associada (mesmo virando duplicata de nome
      # diferente); melhor um duplicado seguro do que apagar trabalho do mestre.
      nonmatch.reject! { |f| dm_customized?(f) }
      return if nonmatch.empty?
      return if matched.empty? || nonmatch.size > matched.size

      nonmatch.each do |f|
        level_record.features.delete(f)
        CharactersFeature.where(feature_id: f.id).delete_all if defined?(CharactersFeature)
        f.reload
        f.destroy! if !f.class_levels.exists? && !f.sub_klass_levels.exists?
      rescue ActiveRecord::InvalidForeignKey
        # mantém a Feature se ainda referenciada; a associação já foi removida.
      end
    end

    def normalize_name(s)
      ActiveSupport::Inflector.transliterate(s.to_s).downcase
        .gsub(/[^a-z0-9]+/, ' ').strip.gsub(/\s+/, ' ')
    end

    # `dm_customized` marca features EDITADAS pelo mestre no compêndio
    # (Admin::LevelFeatureEditor grava esse flag). São sagradas: o sync jamais
    # deve sobrescrever, podar ou destruir essas edições — só stubs do sistema.
    def dm_customized?(feature)
      feature.respond_to?(:dm_customized) && !!feature.dm_customized
    end

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
