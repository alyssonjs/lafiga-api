# frozen_string_literal: true

# Corrige a contaminação das features de classe do Feiticeiro (sorcerer) no DB.
#
# Contexto: o import do SRD (dnd_import.rake) cria, nos níveis onde a SUBCLASSE
# concede características (Nv 6/14/18), placeholders de classe "Sorcerous Origin
# feature" (api_index sorcerous-origin-improvement-1/2/3). Essas características
# já vêm de SubKlassLevel; ao nível de classe elas duplicam e aparecem na ficha
# como "Recurso de origem sorrateira" (tradução errada de "sorcerous").
#
# Esta task remove esses placeholders das ClassLevels do Feiticeiro e apaga as
# Features órfãs. É idempotente, transacional e local (não baixa nada).
# Fonte canônica: .cursor/dnd-rules/classes/feiticeiro/feiticeiro.md
namespace :dnd do
  desc 'Remove placeholders de subclasse (L6/14/18) das ClassLevels do Feiticeiro (idempotente, local)'
  task fix_sorcerer_class_features: :environment do
    placeholder_indexes = %w[
      sorcerous-origin-improvement-1
      sorcerous-origin-improvement-2
      sorcerous-origin-improvement-3
    ]

    klass = Klass.find_by(api_index: 'sorcerer')
    if klass.nil?
      puts '[dnd] Feiticeiro (api_index=sorcerer) não encontrado; nada a fazer.'
      next
    end

    detached = 0
    cache_deleted = 0
    destroyed = 0
    kept = []

    ActiveRecord::Base.transaction do
      features = Feature.where(api_index: placeholder_indexes).to_a
      feature_ids = features.map(&:id)

      # 1) Desassocia das ClassLevels do Feiticeiro (núcleo do fix: é daqui que o
      #    FeaturesAggregator/CharacterSheetSummaryService lista as features de classe).
      features.each do |f|
        klass.class_levels.includes(:features).each do |cl|
          next unless cl.features.include?(f)

          cl.features.delete(f)
          detached += 1
          puts "[dnd] desassociado #{f.api_index.inspect} da ClassLevel L#{cl.level} do Feiticeiro"
        end
      end

      # 2) Limpa o cache denormalizado (characters_features). FeatureGrantService só
      #    concede a partir das class/sub_klass levels e nunca poda — sem isso o
      #    placeholder ficaria pendurado nas fichas que já o sincronizaram.
      if feature_ids.any?
        cache_deleted = CharactersFeature.where(feature_id: feature_ids).delete_all
        puts "[dnd] characters_features removidos (cache denormalizado): #{cache_deleted}"
      end

      # 3) Apaga as Features órfãs (já sem class_levels/sub_klass_levels/characters_features).
      features.each do |f|
        f.reload
        unless f.class_levels.empty? && f.sub_klass_levels.empty?
          kept << f.api_index
          next
        end

        begin
          f.destroy!
          destroyed += 1
          puts "[dnd] Feature órfã apagada: #{f.api_index.inspect}"
        rescue ActiveRecord::InvalidForeignKey => e
          kept << f.api_index
          puts "[dnd] Feature #{f.api_index.inspect} mantida (ainda referenciada): #{e.message.lines.first&.strip}"
        end
      end
    end

    puts "[dnd] Concluído. Associações removidas: #{detached}; cache removido: #{cache_deleted}; Features apagadas: #{destroyed}; mantidas: #{kept.uniq.inspect}."

    remaining = klass.class_levels.includes(:features).order(:level).flat_map do |cl|
      cl.features.select { |f| placeholder_indexes.include?(f.api_index) }.map { |f| "L#{cl.level}:#{f.api_index}" }
    end
    if remaining.any?
      puts "[dnd] AVISO: placeholders ainda presentes: #{remaining.inspect}"
    else
      puts '[dnd] OK: nenhum placeholder de subclasse restante nas ClassLevels do Feiticeiro.'
    end
  end
end
