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
end
