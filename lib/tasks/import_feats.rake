namespace :feats do
  desc "Import feats from YAML file to database"
  task import: :environment do
    puts "=== Importing Feats from YAML ==="
    
    # Load the improved feats YAML
    yaml_file = Rails.root.join('config', 'feats_improved.yml')
    
    unless File.exist?(yaml_file)
      puts "Error: feats_improved.yml not found at #{yaml_file}"
      exit 1
    end
    
    begin
      feats_data = YAML.load_file(yaml_file)
      feats_hash = feats_data['feats']
      
      puts "Found #{feats_hash.keys.length} feats in YAML file"
      
      imported_count = 0
      updated_count = 0
      error_count = 0
      
      # Helper para serializar payload jsonish.
      # Antes usavamos Hash direto -> ActiveRecord chamava `Hash#to_s` em colunas
      # `text` e gerava o formato `"{\"k\"=>v}"` (Ruby Hash#inspect com hashrocket),
      # que NAO eh JSON valido. Resultado: `JSON.parse` falhava em runtime, o
      # `FeatRules.find` devolvia String, e `FeatRules.apply` crashava com
      # TypeError (ex.: bug do Observador da Adimael). Cobertura: ver
      # spec/services/feat_rules_all_feats_shape_spec.rb. `parse_jsonish`
      # tambem aceita o formato corrompido como fallback. Para regravar
      # `Sheet#metadata['feats']` apos mudanca em FeatRules, rodar
      # `rake feats:rebuild_sheets_metadata`.
      to_jsonish = ->(value) { (value || {}).to_json }

      feats_hash.each do |api_index, feat_data|
        begin
          feat_attributes = {
            api_index: api_index,
            name: feat_data['name'],
            description: feat_data['description'],
            prerequisites: to_jsonish.call(feat_data['prerequisites']),
            ability_bonuses: to_jsonish.call(feat_data['ability_bonuses']),
            proficiency_bonuses: to_jsonish.call(feat_data['proficiency_bonuses']),
            cantrips: to_jsonish.call(feat_data['cantrips']),
            spells: to_jsonish.call(feat_data['spells']),
            features: to_jsonish.call(feat_data['features']),
            special_rules: to_jsonish.call(feat_data['special_rules'])
          }
          
          # Check if feat already exists
          existing_feat = Feat.find_by(api_index: api_index)
          
          if existing_feat
            # Update existing feat
            existing_feat.update!(feat_attributes)
            updated_count += 1
            puts "✓ Updated: #{feat_data['name']}"
          else
            # Create new feat
            Feat.create!(feat_attributes)
            imported_count += 1
            puts "✓ Imported: #{feat_data['name']}"
          end
          
        rescue => e
          error_count += 1
          puts "✗ Error with #{api_index}: #{e.message}"
        end
      end
      
      puts "\n=== Import Summary ==="
      puts "Imported: #{imported_count}"
      puts "Updated: #{updated_count}"
      puts "Errors: #{error_count}"
      puts "Total feats in database: #{Feat.count}"
      
    rescue => e
      puts "Error loading YAML file: #{e.message}"
      exit 1
    end
  end
  
  desc "List all feats in database"
  task list: :environment do
    puts "=== Feats in Database ==="
    puts "Total: #{Feat.count}"
    puts
    
    Feat.order(:name).each do |feat|
      special_rules_count = feat.special_rules&.keys&.length || 0
      puts "#{feat.api_index}: #{feat.name} (#{special_rules_count} special rules)"
    end
  end
  
  desc "Show details of a specific feat"
  task :show, [:api_index] => :environment do |t, args|
    if args[:api_index].blank?
      puts "Usage: rails feats:show[api_index]"
      exit 1
    end
    
    feat = Feat.find_by(api_index: args[:api_index])
    
    if feat
      puts "=== Feat: #{feat.name} ==="
      puts "API Index: #{feat.api_index}"
      puts "Description: #{feat.description}"
      puts "Prerequisites: #{feat.prerequisites}"
      puts "Ability Bonuses: #{feat.ability_bonuses}"
      puts "Proficiency Bonuses: #{feat.proficiency_bonuses}"
      puts "Features: #{feat.features}"
      puts "Special Rules: #{feat.special_rules}"
    else
      puts "Feat '#{args[:api_index]}' not found"
    end
  end
end
