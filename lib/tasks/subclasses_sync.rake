# frozen_string_literal: true

namespace :subclasses do
  desc 'Sincroniza SubKlassLevel + Feature a partir de SubKlass#levels_json (idempotente). UPDATE_DESCRIPTIONS=true para sobrescrever descricoes existentes.'
  task sync_levels: :environment do
    update = ENV['UPDATE_DESCRIPTIONS'].to_s.downcase == 'true'
    puts "Sincronizando subclass levels (update_descriptions=#{update})…"
    results = Subclasses::SyncFeaturesFromLevelsJsonService.run_all(
      update_descriptions: update,
      logger: ->(msg) { puts msg },
    )
    by_status = results.group_by(&:status).transform_values(&:size)
    puts "Resumo: #{by_status.inspect}"
  end

  desc 'Sincroniza UMA subclasse (SUB_API_INDEX=batedor [UPDATE_DESCRIPTIONS=true])'
  task sync_one: :environment do
    idx = ENV['SUB_API_INDEX'].to_s
    abort 'Defina SUB_API_INDEX=...' if idx.blank?
    sub = SubKlass.find_by(api_index: idx)
    abort "SubKlass nao encontrada: #{idx}" unless sub
    update = ENV['UPDATE_DESCRIPTIONS'].to_s.downcase == 'true'
    res = Subclasses::SyncFeaturesFromLevelsJsonService.new(sub, update_descriptions: update).call
    puts res.inspect
  end
end
