# frozen_string_literal: true

# Lógica em `app/services/dnd_import_helpers.rb` (carregada pelo Zeitwerk).
# Task independente para aplicar apenas os overrides/grants de subclasses a partir do YAML local
# Não baixa nada da API e não recria ClassLevels

namespace :dnd do
  desc "Aplica overrides/grants de subclasses do YAML local (sem baixar nada, não recria class_levels)"
  task apply_subclass_overrides: :environment do
    puts "Aplicando overrides/grants de subclasses a partir de config/subclass_overrides.yml…"
    Klass.find_each do |klass|
      begin
        DndImportHelpers.apply_subclass_overrides!(klass)
        DndImportHelpers.apply_subclass_grants!(klass)
      rescue => e
        puts "  • Falha ao aplicar overrides para #{klass.name}: #{e.message}"
      end
    end
    puts "Sincronizando SubKlassLevel/Feature a partir de levels_json…"
    results = Subclasses::SyncFeaturesFromLevelsJsonService.run_all(
      logger: ->(msg) { puts msg },
    )
    by_status = results.group_by(&:status).transform_values(&:size)
    puts "Sync subklass features: #{by_status.inspect}"
    puts "Concluído."
  end

  desc "Deduplica subclasses por classe, migrando relacionamentos (seguro para rodar a qualquer momento)"
  task dedup_subclasses: :environment do
    puts "Deduplicando subclasses…"
    Klass.find_each do |klass|
      begin
        puts "- #{klass.name}"
        DndImportHelpers.dedup_subclasses!(klass)
      rescue => e
        puts "  • Falha ao deduplicar #{klass.name}: #{e.message}"
      end
    end
    puts "Concluído."
  end

  desc "Mescla subclasses duplicadas (slug legado) no registro canônico (alvo do apply), repontando fichas. Idempotente e transacional."
  task dedup_subclasses_safe: :environment do
    require 'active_support/inflector'
    slug = ->(s) { ActiveSupport::Inflector.transliterate(s.to_s).downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-+|-+$/, '') }
    over = DndImportHelpers.merged_overrides
    aliases = (DndImportHelpers::SUBCLASS_ALIASES rescue {})
    removed = 0
    moved = 0
    puts "Limpando subclasses duplicadas (mantém o canônico = alvo do apply)…"
    ActiveRecord::Base.transaction do
      Klass.order(:id).each do |klass|
        body = over[klass.api_index.to_s]
        next unless body.is_a?(Hash)
        # Conjunto canônico = api_index que o apply realmente grava (chave do YAML mapeada por SUBCLASS_ALIASES)
        canon_set = body.keys
                        .reject { |x| %w[boons invocations rules].include?(x.to_s) }
                        .select { |x| body[x].is_a?(Hash) }
                        .map { |yk| (aliases[klass.api_index.to_s] && aliases[klass.api_index.to_s][yk.to_s]) || yk.to_s }
        SubKlass.where(klass_id: klass.id).to_a.group_by { |s| slug.call(s.name) }.each do |name_slug, arr|
          next if arr.size <= 1
          canon = arr.select { |s| canon_set.include?(s.api_index.to_s) }
          if canon.size != 1
            # Segurança: não adivinha quando há 0 ou >1 canônico no grupo
            puts "  • PULADO (#{klass.api_index}/#{name_slug}): canônico ambíguo entre #{arr.map(&:api_index).inspect}"
            next
          end
          keep = canon.first
          (arr - [keep]).each do |dup|
            m = SheetKlass.where(sub_klass_id: dup.id).update_all(sub_klass_id: keep.id)
            moved += m
            # Apaga os níveis/magias do stale (evita conflito do índice único ao não migrá-los;
            # o canônico já tem os níveis corretos via apply_subclass_overrides).
            SubKlassLevel.where(sub_klass_id: dup.id).delete_all
            SpellSource.where(source_type: 'SubKlass', source_id: dup.id).delete_all
            dup.destroy!
            removed += 1
            puts "  • #{klass.api_index}: removido ##{dup.id} (#{dup.api_index}) → mantido ##{keep.id} (#{keep.api_index})" + (m.positive? ? " [#{m} ficha(s) repontada(s)]" : "")
          end
        end
      end
    end
    puts "Concluído. Registros removidos: #{removed} | fichas repontadas: #{moved}."
  end
end
