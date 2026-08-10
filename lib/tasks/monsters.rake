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

  desc 'Importa monstros SRD 5.1 da Open5e (snapshot db/seeds/open5e_srd_creatures.json) -> tabela monsters (source=open5e). Ver OPEN5E_MONSTER_IMPORT_PLAN.md'
  task import_open5e: :environment do
    path = Rails.root.join('db', 'seeds', 'open5e_srd_creatures.json')
    unless File.exist?(path)
      puts "Snapshot nao encontrado em #{path}"
      puts 'Baixe o SRD paginando document__key=srd-2014 (ver OPEN5E_MONSTER_IMPORT_PLAN.md > Fase 1).'
      next
    end
    snap      = JSON.parse(File.read(path))
    creatures = snap['creatures'] || snap['results'] || []
    rows      = creatures.map { |c| Open5eMonsterMapper.call(c) }
    result    = MonsterEngineSyncService.call({ 'monsters' => rows }, default_source: 'open5e')

    result.errors.first(20).each { |err| puts "Falhou #{err[:slug]}: #{err[:message]}" }
    puts "Open5e SRD: sync #{result.upserted} (created=#{result.created}, updated=#{result.updated}, " \
         "skipped=#{result.skipped}, errors=#{result.errors.size}) de #{rows.size} mapeados"
  end

  desc 'Reseed open5e: apaga source=open5e e reimporta'
  task reseed_open5e: :environment do
    Monster.where(source: 'open5e').delete_all
    Rake::Task['monsters:import_open5e'].invoke
  end
end
