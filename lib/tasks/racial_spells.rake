# frozen_string_literal: true

namespace :racial_spells do
  desc "List races with innate spells"
  task list_races: :environment do
    puts "🔮 Raças com Magias Inatas:\n\n"
    
    rules = RaceRules.rules
    found_any = false
    
    rules.each do |race_id, race_data|
      # Try both camelCase and snake_case
      innate_spells = race_data[:innateSpells] || race_data[:innate_spells] || race_data['innateSpells'] || race_data['innate_spells']
      next if innate_spells.blank?
      
      found_any = true
      puts "#{race_data[:name] || race_data['name']} (#{race_id}):"
      innate_spells.each do |entry|
        level = entry[:level] || entry['level'] || 1
        spells = (entry[:spells] || entry['spells'] || []).join(', ')
        ability = entry[:ability] || entry['ability'] || 'CHA'
        uses = entry[:uses] || entry['uses'] || '-'
        puts "  Nível #{level}: #{spells} (#{ability}, #{uses})"
      end
      
      # Sub-raças
      subraces = race_data[:subraces] || race_data['subraces'] || {}
      subraces.each do |subrace_id, subrace_data|
        sub_innate = subrace_data[:innateSpells] || subrace_data[:innate_spells] || subrace_data['innateSpells'] || subrace_data['innate_spells']
        next if sub_innate.blank?
        
        puts "  #{subrace_data[:name] || subrace_data['name']} (#{subrace_id}):"
        sub_innate.each do |entry|
          level = entry[:level] || entry['level'] || 1
          spells = (entry[:spells] || entry['spells'] || []).join(', ')
          ability = entry[:ability] || entry['ability'] || 'CHA'
          uses = entry[:uses] || entry['uses'] || '-'
          puts "    Nível #{level}: #{spells} (#{ability}, #{uses})"
        end
      end
      
      puts ""
    end
    
    puts "Nenhuma raça com magias inatas encontrada." unless found_any
  end

  desc "Restore uses for all racial spells (simula long rest)"
  task restore_uses: :environment do
    puts "🔮 Restaurando usos de magias raciais..."
    
    count = SheetKnownSpell.from_race.with_limited_uses.count
    SheetKnownSpell.from_race.with_limited_uses.each(&:restore_uses!)
    
    puts "✅ #{count} magias raciais restauradas"
  end

  desc "Show racial spells for a specific character"
  task :show, [:character_id] => :environment do |t, args|
    character_id = args[:character_id]
    
    unless character_id
      puts "❌ Uso: rake racial_spells:show[CHARACTER_ID]"
      exit 1
    end
    
    character = Character.find(character_id)
    sheet = character.sheet
    
    unless sheet
      puts "❌ Personagem não tem sheet"
      exit 1
    end
    
    puts "🔮 Magias Raciais de #{character.name}:"
    puts "   Raça: #{sheet.race.name}"
    puts "   Sub-raça: #{sheet.sub_race&.name || 'N/A'}"
    puts "   Nível: #{CharacterRules.total_level(sheet)}"
    puts ""
    
    racial_spells = SheetKnownSpell
      .joins(:spell, sheet_klass: :sheet)
      .where(sheets: { id: sheet.id }, source: 'race')
      .order('spells.level ASC, spells.name ASC')
    
    if racial_spells.empty?
      puts "   Nenhuma magia racial encontrada."
    else
      racial_spells.each do |sks|
        spell = sks.spell
        uses_info = if sks.has_uses?
          "(#{sks.uses_remaining}/1 #{sks.uses_per_rest})"
        else
          "(Cantrip)"
        end
        
        puts "   - #{spell.name} (Nível #{spell.level}) #{uses_info}"
      end
    end
  end
end

