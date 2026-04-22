namespace :items do
  desc 'Import all items (equipment + magic items) into items table'
  task import_all: :environment do
    puts '[items] Importing equipment (weapons/armors/shields)'
    Rake::Task['equipment:import_items'].invoke

    if Rake::Task.task_defined?('magic_items:import')
      puts '[items] Importing magic items from config/magic_items.yml'
      Rake::Task['magic_items:import'].invoke
    elsif Rake::Task.task_defined?('equipment:import_magic_items')
      puts '[items] Importing magic items (fallback task)'
      Rake::Task['equipment:import_magic_items'].invoke
    else
      puts '[items] No magic items import task found'
    end

    # Optional: backfill sheet_items.item_id
    if ENV['BACKFILL'] == 'true'
      Rake::Task['items:backfill_sheet_items'].invoke
    end
  end

  desc 'Backfill sheet_items.item_id by matching items via api_index or item_name'
  task backfill_sheet_items: :environment do
    total = 0
    updated = 0
    SheetItem.where(item_id: nil).find_each(batch_size: 500) do |si|
      total += 1
      key = (si.item_index || si.item_name).to_s
      idx = begin
        EquipmentCatalog.normalize_index(key)
      rescue
        key.downcase.strip.gsub(' ', '-')
      end
      item = Item.find_by(api_index: idx)
      if item
        si.update_columns(item_id: item.id)
        updated += 1
      end
    end
    puts "[items] Backfill complete: #{updated}/#{total} sheet_items linked"
  end
end


