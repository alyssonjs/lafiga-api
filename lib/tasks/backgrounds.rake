# frozen_string_literal: true

namespace :backgrounds do
  desc 'Popula/atualiza backgrounds.rules a partir de BackgroundRules::RULES + personalities do YAML PHB'
  task sync_rules: :environment do
    BackgroundRulesImporter.sync_from_code_and_yaml!
    puts '✓ Background.rules sincronizado (PHB + YAML). Cache de BackgroundRules invalidado.'
  end

  desc 'Importa variantes PHB (config/background_variants_phb.yml) como Background + parent_api_index'
  task seed_phb_variants: :environment do
    BackgroundVariantImporter.import_from_yaml!
    puts '✓ Variações PHB importadas. Cache invalidado.'
  end
end
