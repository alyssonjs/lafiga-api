# api/lib/tasks/equipment_audit.rake
namespace :dnd do
  namespace :equipment do
    desc 'Verifica personagens sem equipamentos e atrela equipamentos baseados nas proficiências'
    task audit_and_assign: :environment do
      puts '== Auditoria de Equipamentos =='
      
      # Buscar personagens sem equipamentos
      sheets_without_equipment = Sheet.joins(:character)
        .left_joins(:sheet_items)
        .where(sheet_items: { id: nil })
        .includes(:character, :race, sheet_klasses: [:klass])
      
      puts "Encontrados #{sheets_without_equipment.count} personagens sem equipamentos"
      
      if sheets_without_equipment.empty?
        puts 'Todos os personagens já possuem equipamentos!'
        return
      end
      
      # Processar cada personagem
      assigned_count = 0
      errors = []
      
      sheets_without_equipment.each do |sheet|
        begin
          puts "\nProcessando: #{sheet.character.name} (#{sheet.race.name})"
          
          # Obter proficiências da classe
          klass = sheet.sheet_klasses.first&.klass
          next unless klass
          
          puts "  Classe: #{klass.name}"
          
          # Obter regras da classe
          class_rule = ClassRules.find(klass.api_index)
          next unless class_rule
          
          # Extrair proficiências
          armor_profs = Array(class_rule[:armor_proficiencies])
          weapon_profs = Array(class_rule[:weapon_proficiencies])
          
          puts "  Proficiências em armadura: #{armor_profs.join(', ')}"
          puts "  Proficiências em armas: #{weapon_profs.join(', ')}"
          
          # Atribuir equipamentos baseados nas proficiências
          equipment_items = []
          
          # 1. Armadura baseada na proficiência
          armor_item = select_armor_for_proficiencies(armor_profs, sheet)
          if armor_item
            equipment_items << {
              item_index: armor_item[:index],
              item_name: armor_item[:name],
              category: 'armor',
              quantity: 1,
              equipped: true,
              slot: 'armor',
              source: 'auto_assigned',
              props_json: armor_item[:props] || {}
            }
            puts "  ✓ Armadura: #{armor_item[:name]}"
          end
          
          # 2. Escudo se proficiente
          if armor_profs.any? { |p| p.include?('escudo') || p.include?('shield') }
            shield_item = {
              item_index: 'shield',
              item_name: 'Escudo',
              category: 'shield',
              quantity: 1,
              equipped: true,
              slot: 'shield',
              source: 'auto_assigned',
              props_json: { ac_bonus: 2 }
            }
            equipment_items << shield_item
            puts "  ✓ Escudo: Escudo"
          end
          
          # 3. Armas baseadas na proficiência
          weapons = select_weapons_for_proficiencies(weapon_profs, sheet)
          weapons.each_with_index do |weapon, index|
            slot = index == 0 ? 'main_hand' : 'off_hand'
            equipment_items << {
              item_index: weapon[:index],
              item_name: weapon[:name],
              category: 'weapon',
              quantity: 1,
              equipped: true,
              slot: slot,
              source: 'auto_assigned',
              props_json: weapon[:props] || {}
            }
            puts "  ✓ Arma #{index + 1}: #{weapon[:name]} (#{slot})"
          end
          
          # 4. Munição se necessário
          ammunition = select_ammunition_for_weapons(weapons)
          ammunition.each do |ammo|
            equipment_items << {
              item_index: ammo[:index],
              item_name: ammo[:name],
              category: 'ammunition',
              quantity: ammo[:quantity],
              equipped: false,
              slot: nil,
              source: 'auto_assigned',
              props_json: {}
            }
            puts "  ✓ Munição: #{ammo[:name]} (#{ammo[:quantity]})"
          end
          
          # Criar equipamentos usando o serviço
          if equipment_items.any?
            result = StartingEquipmentService.call(sheet: sheet, items: equipment_items)
            if result.success?
              assigned_count += 1
              puts "  ✓ #{equipment_items.count} equipamentos atribuídos com sucesso"
            else
              errors << "#{sheet.character.name}: #{result.errors.full_messages.join(', ')}"
              puts "  ✗ Erro: #{result.errors.full_messages.join(', ')}"
            end
          else
            puts "  ⚠ Nenhum equipamento adequado encontrado"
          end
          
        rescue => e
          error_msg = "#{sheet.character.name}: #{e.message}"
          errors << error_msg
          puts "  ✗ Erro: #{e.message}"
        end
      end
      
      # Relatório final
      puts "\n== Relatório Final =="
      puts "Personagens processados: #{sheets_without_equipment.count}"
      puts "Equipamentos atribuídos com sucesso: #{assigned_count}"
      puts "Erros: #{errors.count}"
      
      if errors.any?
        puts "\nErros encontrados:"
        errors.each { |error| puts "  - #{error}" }
      end
      
      puts "\nAuditoria concluída!"
    end
    
    desc 'Lista personagens sem equipamentos'
    task list_empty: :environment do
      puts '== Personagens sem Equipamentos =='
      
      sheets_without_equipment = Sheet.joins(:character)
        .left_joins(:sheet_items)
        .where(sheet_items: { id: nil })
        .includes(:character, :race, sheet_klasses: [:klass])
      
      if sheets_without_equipment.empty?
        puts 'Todos os personagens possuem equipamentos!'
        return
      end
      
      sheets_without_equipment.each do |sheet|
        klass = sheet.sheet_klasses.first&.klass
        puts "#{sheet.character.name} - #{sheet.race.name} #{klass&.name || 'Sem classe'}"
      end
      
      puts "\nTotal: #{sheets_without_equipment.count} personagens"
    end
    
    desc 'Verifica consistência dos equipamentos existentes'
    task verify_consistency: :environment do
      puts '== Verificação de Consistência de Equipamentos =='
      
      issues = []
      
      Sheet.includes(:character, :sheet_items, sheet_klasses: [:klass]).each do |sheet|
        klass = sheet.sheet_klasses.first&.klass
        next unless klass
        
        class_rule = ClassRules.find(klass.api_index)
        next unless class_rule
        
        armor_profs = Array(class_rule[:armor_proficiencies])
        weapon_profs = Array(class_rule[:weapon_proficiencies])
        
        # Verificar armaduras equipadas
        equipped_armor = sheet.sheet_items.where(equipped: true, slot: 'armor').first
        if equipped_armor
          unless can_wear_armor?(equipped_armor, armor_profs)
            issues << "#{sheet.character.name}: Armadura #{equipped_armor.item_name} sem proficiência"
          end
        end
        
        # Verificar escudos equipados
        equipped_shield = sheet.sheet_items.where(equipped: true, slot: 'shield').first
        if equipped_shield
          unless armor_profs.any? { |p| p.include?('escudo') || p.include?('shield') }
            issues << "#{sheet.character.name}: Escudo sem proficiência"
          end
        end
        
        # Verificar armas equipadas
        equipped_weapons = sheet.sheet_items.where(equipped: true, slot: ['main_hand', 'off_hand'])
        equipped_weapons.each do |weapon|
          unless can_wield_weapon?(weapon, weapon_profs)
            issues << "#{sheet.character.name}: Arma #{weapon.item_name} sem proficiência"
          end
        end
      end
      
      if issues.empty?
        puts 'Nenhum problema de consistência encontrado!'
      else
        puts "Encontrados #{issues.count} problemas:"
        issues.each { |issue| puts "  - #{issue}" }
      end
    end
  end
end

# Métodos auxiliares
def select_armor_for_proficiencies(armor_profs, sheet)
  # Prioridade: pesada > média > leve
  if armor_profs.any? { |p| p.include?('pesada') || p.include?('heavy') }
    return {
      index: 'chain-mail',
      name: 'Cota de Malha',
      props: { ac_base: 16, dex_cap: 0, stealth_disadvantage: true, str_req: 13 }
    }
  elsif armor_profs.any? { |p| p.include?('média') || p.include?('medium') }
    return {
      index: 'chain-shirt',
      name: 'Camisa de Cota de Malha',
      props: { ac_base: 13, dex_cap: 2, stealth_disadvantage: false }
    }
  elsif armor_profs.any? { |p| p.include?('leve') || p.include?('light') }
    return {
      index: 'leather',
      name: 'Couro',
      props: { ac_base: 11, dex_cap: nil, stealth_disadvantage: false }
    }
  end
  
  nil
end

def select_weapons_for_proficiencies(weapon_profs, sheet)
  weapons = []
  
  # Verificar se tem proficiência em armas marciais
  has_martial = weapon_profs.any? { |p| p.include?('marciais') || p.include?('martial') }
  has_simple = weapon_profs.any? { |p| p.include?('simples') || p.include?('simple') }
  
  # Arma principal
  if has_martial
    weapons << {
      index: 'longsword',
      name: 'Espada Longa',
      props: { 
        type: 'melee', 
        hands: 1, 
        versatile: true, 
        category: 'martial', 
        damage_die: '1d8', 
        versatile_die: '1d10' 
      }
    }
  elsif has_simple
    weapons << {
      index: 'spear',
      name: 'Lança',
      props: { 
        type: 'melee', 
        hands: 1, 
        versatile: true, 
        thrown: true, 
        range: '20/60', 
        category: 'simple', 
        damage_die: '1d6', 
        versatile_die: '1d8' 
      }
    }
  end
  
  # Arma secundária (se proficiente em armas leves)
  if weapon_profs.any? { |p| p.include?('leve') || p.include?('light') } || 
     weapon_profs.any? { |p| p.include?('adaga') || p.include?('dagger') }
    weapons << {
      index: 'dagger',
      name: 'Adaga',
      props: { 
        type: 'melee', 
        hands: 1, 
        light: true, 
        finesse: true, 
        thrown: true, 
        range: '20/60', 
        category: 'simple', 
        damage_die: '1d4' 
      }
    }
  end
  
  weapons
end

def select_ammunition_for_weapons(weapons)
  ammunition = []
  
  weapons.each do |weapon|
    case weapon[:index]
    when 'longbow', 'shortbow'
      ammunition << { index: 'arrow', name: 'Seta', quantity: 20 }
    when 'light-crossbow', 'heavy-crossbow'
      ammunition << { index: 'bolt', name: 'Virote', quantity: 20 }
    when 'sling'
      ammunition << { index: 'sling-bullet', name: 'Projétil de Funda', quantity: 20 }
    when 'blowgun'
      ammunition << { index: 'blowgun-needle', name: 'Agulha de Zarabatana', quantity: 20 }
    end
  end
  
  ammunition.uniq { |ammo| ammo[:index] }
end

def can_wear_armor?(armor_item, armor_profs)
  armor_name = armor_item.item_name.downcase
  armor_index = armor_item.item_index.downcase
  
  # Verificar por categoria
  if armor_index.include?('chain-mail') || armor_index.include?('plate') || armor_index.include?('splint')
    return armor_profs.any? { |p| p.include?('pesada') || p.include?('heavy') }
  elsif armor_index.include?('chain-shirt') || armor_index.include?('breastplate') || armor_index.include?('half-plate')
    return armor_profs.any? { |p| p.include?('média') || p.include?('medium') }
  elsif armor_index.include?('leather') || armor_index.include?('padded') || armor_index.include?('studded')
    return armor_profs.any? { |p| p.include?('leve') || p.include?('light') }
  end
  
  # Fallback: verificar se tem alguma proficiência em armadura
  armor_profs.any? { |p| p.include?('armadura') || p.include?('armor') }
end

def can_wield_weapon?(weapon_item, weapon_profs)
  weapon_name = weapon_item.item_name.downcase
  weapon_index = weapon_item.item_index.downcase
  
  # Verificar por categoria
  if weapon_index.include?('longsword') || weapon_index.include?('greatsword') || weapon_index.include?('rapier')
    return weapon_profs.any? { |p| p.include?('marciais') || p.include?('martial') }
  elsif weapon_index.include?('spear') || weapon_index.include?('dagger') || weapon_index.include?('club')
    return weapon_profs.any? { |p| p.include?('simples') || p.include?('simple') }
  end
  
  # Verificar por nome específico
  weapon_profs.any? do |prof|
    prof.downcase.include?(weapon_name) || prof.downcase.include?(weapon_index)
  end
end