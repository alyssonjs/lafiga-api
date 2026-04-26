namespace :magic_items do
  desc 'Import magic items into items table from YAML at api/config/magic_items.yml'
  task import: :environment do
    path = Rails.root.join('config','magic_items.yml')
    unless File.exist?(path)
      puts "YAML not found at #{path}"
      next
    end
    yaml = YAML.safe_load(File.read(path)) || {}
    data = yaml['magic_items'] || {}
    imported = 0
    data.each do |key, row|
      begin
        name = row['name'] || key.to_s.tr('-', ' ')
        api_index = EquipmentCatalog.normalize_index(key) rescue key.to_s
        weight_kg = to_kg(row['weight'])
        props = (row['props'] || {})
        new_cat, is_w = MagicItemEngineSyncService.category_and_wondrous_for_yaml_row(row)
        item = Item.find_or_initialize_by(api_index: api_index)
        item.assign_attributes(
          name: name,
          kind: 'magic_item',
          category: new_cat,
          sub_category: row['sub_category'],
          is_wondrous: is_w,
          rarity: row['rarity'],
          requires_attunement: !!row['requires_attunement'],
          attunement_note: row['attunement_note'],
          weight_kg: weight_kg,
          value_gp: row['value_gp'],
          source: row['source'],
          description: row['description'],
          tags: Array(row['tags']),
          props: props
        )
        item.save! if item.changed?
        imported += 1
      rescue => e
        puts "Failed to import #{key}: #{e.message}"
      end
    end
    puts "Imported/updated #{imported} magic items into items table"
  end

  desc 'Sync YAML magic_items into magic_items table (used by MagicItemRules engine)'
  task sync_engine: :environment do
    path = Rails.root.join('config','magic_items.yml')
    unless File.exist?(path)
      puts "YAML not found at #{path}"
      next
    end
    result = MagicItemEngineSyncService.call(File.read(path))
    result.errors.each { |err| puts "Failed sync_engine for #{err[:slug]}: #{err[:message]}" }
    puts "Synced #{result.upserted} entries into magic_items table (created=#{result.created}, updated=#{result.updated}, skipped=#{result.skipped}, errors=#{result.errors.size})"
  end

  def to_kg(val)
    MagicItemEngineSyncService.to_kg(val)
  end

  desc 'Importa o seed magic_items_accessories_bootstrap.yml (anéis, maravilhosos, varinhas, bastões, cajados) em magic_items e items — categorias API inalteradas; abas do compêndio são só no front'
  task import_accessories_bootstrap: :environment do
    path = Rails.root.join('config', 'magic_items_accessories_bootstrap.yml')
    unless File.exist?(path)
      puts "YAML not found at #{path}"
      next
    end
    yaml = File.read(path)
    result = MagicItemEngineSyncService.call(yaml)
    result.errors.each { |err| puts "Failed sync_engine for #{err[:slug]}: #{err[:message]}" }
    puts "magic_items: synced #{result.upserted} (created=#{result.created}, updated=#{result.updated}, errors=#{result.errors.size})"

    data = (YAML.safe_load(yaml) || {})['magic_items'] || {}
    items_imported = 0
    data.each do |key, row|
      begin
        name = row['name'] || key.to_s.tr('-', ' ')
        api_index = EquipmentCatalog.normalize_index(key)
        new_cat, is_w = MagicItemEngineSyncService.category_and_wondrous_for_yaml_row(row)
        item = Item.find_or_initialize_by(api_index: api_index)
        item.assign_attributes(
          name: name,
          kind: 'magic_item',
          category: new_cat,
          sub_category: row['sub_category'],
          is_wondrous: is_w,
          rarity: row['rarity'],
          requires_attunement: !!row['requires_attunement'],
          attunement_note: row['attunement_note'],
          weight_kg: to_kg(row['weight']),
          value_gp: row['value_gp'],
          source: row['source'],
          description: row['description'],
          tags: Array(row['tags']),
          props: (row['props'] || {}),
        )
        item.save! if item.changed?
        items_imported += 1
      rescue => e
        puts "Failed Item import for #{key}: #{e.message}"
      end
    end
    puts "items: imported/updated #{items_imported} rows"
  end

  desc 'Importa config/magic_items_wardrobe_compendium_import.yml (67 itens: anéis + peças de vestuário) em magic_items e items — usar em prod após dry_run no bulk_import'
  task import_wardrobe_compendium_pack: :environment do
    path = Rails.root.join('config', 'magic_items_wardrobe_compendium_import.yml')
    unless File.exist?(path)
      puts "YAML not found at #{path}"
      next
    end
    yaml = File.read(path)
    result = MagicItemEngineSyncService.call(yaml)
    result.errors.each { |err| puts "Failed sync for #{err[:slug]}: #{err[:message]}" }
    puts "magic_items: synced #{result.upserted} (created=#{result.created}, updated=#{result.updated}, errors=#{result.errors.size})"

    data = (YAML.safe_load(yaml) || {})['magic_items'] || {}
    items_imported = 0
    data.each do |key, row|
      begin
        name = row['name'] || key.to_s.tr('-', ' ')
        api_index = EquipmentCatalog.normalize_index(key)
        new_cat, is_w = MagicItemEngineSyncService.category_and_wondrous_for_yaml_row(row)
        item = Item.find_or_initialize_by(api_index: api_index)
        item.assign_attributes(
          name: name,
          kind: 'magic_item',
          category: new_cat,
          sub_category: row['sub_category'],
          is_wondrous: is_w,
          rarity: row['rarity'],
          requires_attunement: !!row['requires_attunement'],
          attunement_note: row['attunement_note'],
          weight_kg: to_kg(row['weight']),
          value_gp: row['value_gp'],
          source: row['source'],
          description: row['description'],
          tags: Array(row['tags']),
          props: (row['props'] || {}),
        )
        item.save! if item.changed?
        items_imported += 1
      rescue => e
        puts "Failed Item import for #{key}: #{e.message}"
      end
    end
    puts "items: imported/updated #{items_imported} rows"
  end
end

