namespace :monsters do
  desc 'Import monsters into monsters table from JSON at api/db/seeds/monsters.json (gerado pelo dump do front)'
  task import: :environment do
    path = Rails.root.join('db', 'seeds', 'monsters.json')
    unless File.exist?(path)
      puts "JSON not found at #{path}"
      puts "Gere com: cd front-lafiga && npx tsx scripts/dumpMonstersToJson.ts"
      next
    end

    raw    = JSON.parse(File.read(path))
    result = MonsterEngineSyncService.call(raw, default_source: raw['source'] || 'srd')

    result.errors.each { |err| puts "Failed import for #{err[:slug]}: #{err[:message]}" }
    puts "Synced #{result.upserted} monsters (created=#{result.created}, updated=#{result.updated}, skipped=#{result.skipped}, errors=#{result.errors.size})"
  end

  desc 'Import monsters from a YAML file at api/config/monsters.yml (homebrew workflow)'
  task import_yaml: :environment do
    path = Rails.root.join('config', 'monsters.yml')
    unless File.exist?(path)
      puts "YAML not found at #{path}"
      next
    end
    result = MonsterEngineSyncService.call(File.read(path))
    puts "Synced #{result.upserted} monsters from YAML (created=#{result.created}, updated=#{result.updated}, errors=#{result.errors.size})"
  end

  desc 'Reseed: apaga TODOS os monstros com source=srd e re-importa do dump'
  task reseed: :environment do
    Monster.where(source: 'srd').delete_all
    Rake::Task['monsters:import'].invoke
  end
end
