# Usar usuário existente
user = User.find(14)

# Criar personagem
character = Character.create!(
  name: 'Thorin Escudodeferro',
  background: 'Um anão guerreiro corajoso',
  user: user
)

puts "Personagem criado: #{character.name} (ID: #{character.id})"

# Criar sheet com dados normalizados
sheet = Sheet.create!(
  character: character,
  race_id: 16, # Anão
  sub_race_id: 24, # Anão da Montanha
  str: 16,
  dex: 10,
  con: 14,
  int: 12,
  wis: 13,
  cha: 8,
  hp_max: 12,
  hp_current: 12,
  temp_hp: 0,
  current_level: 1,
  alignment_id: 5, # Lawful Good
  background_id: 12, # Soldier
  background_key: 'soldier',
  race_choices: {'dwarfTool' => 'Ferramentas de ferreiro'},
  class_choices: {
    'subclass_id' => 'champion',
    'fighting_style' => 'defense',
    'per_level' => {
      '1' => {
        'asi' => {'choices' => {}},
        'skills' => ['Atletismo', 'Intimidação'],
        'spells' => [],
        'cantrips' => [],
        'prepared' => [],
        'instruments' => [],
        'subclass_id' => nil,
        'fighting_style' => 'defense'
      }
    }
  },
  race_summary: {
    'speed_ft' => 25,
    'speed_m' => 8,
    'darkvision' => {'range' => 60},
    'languages' => ['Comum', 'Anão'],
    'traits' => ['dwarven_resilience', 'stonecunning', 'darkvision'],
    'proficiencies' => {
      'weapons' => ['machado de batalha', 'martelo de guerra'],
      'tools' => {'choiceCount' => 1, 'choices' => ['Ferramentas de ferreiro']}
    }
  },
  class_summary: {
    'klass_id' => 'fighter',
    'name' => 'Guerreiro',
    'hit_die' => 'd10',
    'primary_abilities' => ['STR', 'CON'],
    'saving_throws' => ['STR', 'CON'],
    'armor_proficiencies' => ['leve', 'média', 'pesada', 'escudos'],
    'weapon_proficiencies' => ['armas simples', 'armas marciais'],
    'tools' => [],
    'skills' => ['Atletismo', 'Intimidação'],
    'fighting_style' => 'defense',
    'subclass' => 'champion',
    'spellcasting' => nil,
    'current_level' => 1
  },
  features_by_level: {
    '1' => [
      {
        'id' => 1,
        'api_index' => 'fighting-style',
        'name' => 'Estilo de Combate',
        'category' => 'class_feature',
        'description' => 'Você adota um estilo particular de combate como sua especialidade.'
      },
      {
        'id' => 2,
        'api_index' => 'second-wind',
        'name' => 'Segundo Fôlego',
        'category' => 'class_feature',
        'description' => 'Você tem uma reserva limitada de resistência que pode usar para se proteger do perigo.'
      }
    ]
  },
  race_bonuses_applied: {'con' => 2, 'str' => 2},
  metadata: {
    'race_choices' => {'dwarfTool' => 'Ferramentas de ferreiro'},
    'background' => 'Soldado',
    'background_key' => 'soldier',
    'alignment' => {'index' => 'lawful-good', 'name' => 'Lawful Good', 'desc' => 'Lawful good (LG) creatures can be counted on to do the right thing as expected by society.'},
    'current_level' => 1
  }
)

puts "Sheet criada com sucesso!"
puts "Sheet ID: #{sheet.id}"
puts "Nível: #{sheet.current_level}"
puts "Raça: #{sheet.race.name}"
puts "Classe: #{sheet.class_summary['name']}"
puts "Alinhamento: #{sheet.alignment.name}"
puts "Antecedente: #{sheet.background.name}"
puts "Colunas normalizadas funcionando!"
puts "Race choices: #{sheet.race_choices}"
puts "Class choices: #{sheet.class_choices['subclass_id']}"
puts "Race summary: #{sheet.race_summary['speed_ft']}ft speed"
puts "Features by level: #{sheet.features_by_level.keys.join(', ')}"
puts "Race bonuses: #{sheet.race_bonuses_applied}"
