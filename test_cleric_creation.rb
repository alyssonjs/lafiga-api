# frozen_string_literal: true

# Script de teste para criação de Clérigo
puts "🧪 TESTE: Criação de Clérigo via CharacterProvisioningService"
puts "=" * 70

# 1. Buscar catálogos
puts "\n📚 Buscando catálogos..."
human_race = Race.find_by(api_index: 'human')
cleric_class = Klass.find_by(api_index: 'cleric')
life_domain = SubKlass.find_by(api_index: 'life')

unless human_race && cleric_class
  puts "❌ Catálogos incompletos!"
  exit 1
end

puts "✅ Raça: #{human_race.name} (ID: #{human_race.id})"
puts "✅ Classe: #{cleric_class.name} (ID: #{cleric_class.id})"
puts "✅ Subclasse: #{life_domain&.name || 'N/A'} (ID: #{life_domain&.id})"

# 2. Buscar magias
puts "\n✨ Buscando magias..."
sacred_flame = Spell.where("name ILIKE ?", "%sacred%flame%").or(Spell.where("name ILIKE ?", "%chama%sagrada%")).first
guidance = Spell.where("name ILIKE ?", "%guidance%").or(Spell.where("name ILIKE ?", "%orientação%")).first
thaumaturgy = Spell.where("name ILIKE ?", "%thaumaturgy%").or(Spell.where("name ILIKE ?", "%taumaturgia%")).first

puts "  Cantrips:"
puts "    - #{sacred_flame&.name} (ID: #{sacred_flame&.id})"
puts "    - #{guidance&.name} (ID: #{guidance&.id})"
puts "    - #{thaumaturgy&.name} (ID: #{thaumaturgy&.id})"

# 3. Criar usuário de teste
puts "\n👤 Criando usuário de teste..."
player_role = Role.find_or_create_by!(name: "player")
user = User.find_or_create_by!(email: "test_cleric@lafiga.com") do |u|
  u.username = "test_cleric"
  u.password = "password123"
  u.password_confirmation = "password123"
  u.role_id = player_role.id
end
puts "✅ Usuário: #{user.email} (ID: #{user.id}, Role: #{user.role&.name})"

# 4. Montar payload
puts "\n📦 Montando payload..."
payload = {
  character: {
    name: "Theron Lightbringer",
    background: "Acólito",
    status: "active"
  },
  wizard: {
    race: {
      raceId: human_race.id,
      subRaceId: nil,
      abilityMethod: 'roll_4d6',
      rolledScores: [10, 12, 14, 8, 16, 13],
      attributes: { str: 10, dex: 12, con: 14, int: 8, wis: 16, cha: 13 },
      raceChoices: {}
    },
    background: {
      backgroundKey: "acolyte",
      backgroundName: "Acólito",
      backgroundProfs: ["insight", "religion"],
      backgroundChoices: {}
    },
    klass: {
      klassId: cleric_class.id,
      classSubclassId: life_domain&.id,
      level: 3,
      classSkillPicks: ["history", "medicine"],
      classInstrumentPicks: [],
      classFightingStyle: nil,
      pickedCantrips: [
        sacred_flame,
        guidance,
        thaumaturgy
      ].compact.map { |s| { id: s.id, name: s.name } },
      pickedSpells: [],
      classPicksByLevel: {
        1 => {
          skills: ["history", "medicine"],
          cantrips: [sacred_flame, guidance, thaumaturgy].compact.map { |s| { id: s.id, name: s.name } },
          spells: [],
          prepared: [],
          subclass_id: life_domain&.id,
          hp_gain: { roll: 8, con_mod: 2, total: 10 }
        },
        2 => {
          skills: [],
          cantrips: [],
          spells: [],
          prepared: [],
          hp_gain: { roll: 5, con_mod: 2, total: 7 }
        },
        3 => {
          skills: [],
          cantrips: [],
          spells: [],
          prepared: [],
          hp_gain: { roll: 5, con_mod: 2, total: 7 }
        }
      }
    },
    equipment: {
      equipmentPicks: []
    },
    meta: {
      name: "Theron Lightbringer",
      alignmentKey: "lawful-good"
    }
  }
}

# 5. Executar serviço
puts "\n🚀 Executando CharacterProvisioningService..."
result = CharacterProvisioningService.call(user: user, payload: payload)

if result.success?
  puts "\n✅ SUCESSO! Personagem criado!"
  
  char = result.result[:character]
  puts "\n📋 CHARACTER:"
  puts "  ID: #{char.id}"
  puts "  Nome: #{char.name}"
  puts "  Background: #{char.background}"
  puts "  Status: #{char.status}"
  puts "  User ID: #{char.user_id}"
  
  if char.sheet
    sheet = char.sheet
    puts "\n📊 SHEET:"
    puts "  ID: #{sheet.id}"
    puts "  Raça: #{sheet.race&.name}"
    puts "  Sub-raça: #{sheet.sub_race&.name || 'N/A'}"
    puts "  Atributos:"
    puts "    FOR #{sheet.str}, DES #{sheet.dex}, CON #{sheet.con}"
    puts "    INT #{sheet.int}, SAB #{sheet.wis}, CAR #{sheet.cha}"
    puts "  HP: #{sheet.hp_current}/#{sheet.hp_max}"
    puts "  Metadata keys: #{sheet.metadata.keys.join(', ')}"
    
    sk = sheet.sheet_klasses.first
    if sk
      puts "\n🎓 SHEET_KLASS:"
      puts "  ID: #{sk.id}"
      puts "  Classe: #{sk.klass&.name} (#{sk.klass&.api_index})"
      puts "  Subclasse: #{sk.sub_klass&.name} (#{sk.sub_klass&.api_index})"
      puts "  Nível: #{sk.level}"
      
      known_count = SheetKnownSpell.where(sheet_klass: sk).count
      prepared_count = SheetPreparedSpell.where(sheet_klass: sk).count
      
      puts "\n✨ MAGIAS:"
      puts "  Conhecidas: #{known_count}"
      puts "  Preparadas: #{prepared_count}"
      
      if known_count > 0
        puts "\n  📖 Magias Conhecidas:"
        SheetKnownSpell.where(sheet_klass: sk).includes(:spell).order('spells.level, spells.name').each do |sks|
          uses = sks.uses_per_rest ? " (#{sks.uses_remaining || 0}/#{sks.uses_per_rest})" : ""
          puts "    - #{sks.spell.name} (L#{sks.spell.level}) [#{sks.source}]#{uses}"
        end
      end
      
      if prepared_count > 0
        puts "\n  📚 Magias Preparadas:"
        SheetPreparedSpell.where(sheet_klass: sk).includes(:spell).order('spells.level, spells.name').each do |sps|
          always = sps.always_prepared ? " [ALWAYS]" : ""
          puts "    - #{sps.spell.name} (L#{sps.spell.level})#{always}"
        end
      end
      
      features_count = Feature.where(source_type: 'SubKlass', source_id: sk.sub_klass_id).count
      puts "\n🎯 FEATURES:"
      puts "  Total: #{features_count}"
      if features_count > 0
        Feature.where(source_type: 'SubKlass', source_id: sk.sub_klass_id).order(:level).limit(5).each do |f|
          puts "    - #{f.name} (Level #{f.level})"
        end
      end
    end
    
    items_count = SheetItem.where(sheet: sheet).count
    puts "\n🎒 EQUIPMENT:"
    puts "  Total de itens: #{items_count}"
    if items_count > 0
      SheetItem.where(sheet: sheet).includes(:item).limit(5).each do |si|
        equipped = si.equipped ? " [EQUIPPED]" : ""
        puts "    - #{si.item.name} x#{si.quantity}#{equipped}"
      end
    end
  else
    puts "\n❌ Sheet não criada!"
  end
  
  puts "\n" + "=" * 70
  puts "✅ TESTE CONCLUÍDO COM SUCESSO!"
  puts "=" * 70
  
else
  puts "\n❌ FALHA ao criar personagem:"
  result.errors.full_messages.each do |error|
    puts "  - #{error}"
  end
  puts "\n" + "=" * 70
  puts "❌ TESTE FALHOU!"
  puts "=" * 70
  exit 1
end

