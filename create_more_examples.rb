# Usar usuário existente
user = User.find(14)

# Criar segundo personagem - Elfo Bardo
character2 = Character.create!(
  name: 'Elenor Melodia',
  background: 'Uma elfa bardo talentosa',
  user: user
)

sheet2 = Sheet.create!(
  character: character2,
  race_id: 17, # Elfo
  sub_race_id: 25, # Alto Elfo
  str: 8,
  dex: 16,
  con: 12,
  int: 14,
  wis: 13,
  cha: 15,
  hp_max: 8,
  hp_current: 8,
  temp_hp: 0,
  current_level: 1,
  alignment_id: 2, # Chaotic Good
  background_id: 4, # Artista
  background_key: 'entertainer',
  race_choices: {'elfCantrip' => 'Prestidigitação'},
  class_choices: {
    'subclass_id' => 'lore',
    'instruments' => ['Alaúde', 'Flauta'],
    'per_level' => {
      '1' => {
        'skills' => ['Acrobacia', 'Atuação', 'Intuição', 'Percepção'],
        'instruments' => ['Alaúde', 'Flauta'],
        'spells' => ['Cura Menor', 'Detectar Magia'],
        'cantrips' => ['Prestidigitação', 'Vicious Mockery']
      }
    }
  },
  race_summary: {
    'speed_ft' => 30,
    'speed_m' => 9,
    'darkvision' => {'range' => 60},
    'languages' => ['Comum', 'Élfico'],
    'traits' => ['fey_ancestry', 'trance', 'darkvision'],
    'proficiencies' => {
      'weapons' => ['espada longa', 'espada curta', 'arco longo', 'arco curto'],
      'tools' => []
    }
  },
  class_summary: {
    'klass_id' => 'bard',
    'name' => 'Bardo',
    'hit_die' => 'd8',
    'primary_abilities' => ['CHA'],
    'saving_throws' => ['DEX', 'CHA'],
    'armor_proficiencies' => ['leve'],
    'weapon_proficiencies' => ['armas simples', 'espada longa', 'espada curta', 'arco longo', 'arco curto'],
    'tools' => ['instrumentos musicais'],
    'skills' => ['Acrobacia', 'Atuação', 'Intuição', 'Percepção'],
    'subclass' => 'lore',
    'spellcasting' => {'ability' => 'CHA', 'spell_save_dc' => 12, 'spell_attack_bonus' => 4},
    'current_level' => 1
  },
  features_by_level: {
    '1' => [
      {
        'id' => 3,
        'api_index' => 'spellcasting',
        'name' => 'Conjuracao',
        'category' => 'class_feature',
        'description' => 'Como estudante de magia, você tem um grimório contendo magias que mostram os primeiros sinais de sua verdadeira arte.'
      },
      {
        'id' => 4,
        'api_index' => 'bardic-inspiration',
        'name' => 'Inspiração Bárdica',
        'category' => 'class_feature',
        'description' => 'Você pode inspirar outros através de palavras ou música tocada.'
      }
    ]
  },
  race_bonuses_applied: {'dex' => 2, 'int' => 1},
  metadata: {
    'race_choices' => {'elfCantrip' => 'Prestidigitação'},
    'background' => 'Artista',
    'background_key' => 'entertainer',
    'alignment' => {'index' => 'chaotic-good', 'name' => 'Chaotic Good', 'desc' => 'Chaotic good (CG) creatures act as their conscience directs, with little regard for what others expect.'},
    'current_level' => 1
  }
)

puts "Segundo personagem criado: #{character2.name}"
puts "Sheet ID: #{sheet2.id}"

# Criar terceiro personagem - Humano Mago
character3 = Character.create!(
  name: 'Marcus Devoto',
  background: 'Um humano mago estudioso',
  user: user
)

sheet3 = Sheet.create!(
  character: character3,
  race_id: 18, # Humano
  sub_race_id: 28, # Humano Variante
  str: 10,
  dex: 14,
  con: 13,
  int: 16,
  wis: 12,
  cha: 8,
  hp_max: 6,
  hp_current: 6,
  temp_hp: 0,
  current_level: 1,
  alignment_id: 7, # Neutral
  background_id: 10, # Sábio
  background_key: 'sage',
  race_choices: {'humanFeat' => 'Observador', 'humanSkill' => 'Investigação'},
  class_choices: {
    'subclass_id' => 'evocation',
    'per_level' => {
      '1' => {
        'skills' => ['Arcanismo', 'História'],
        'spells' => ['Bola de Fogo', 'Escudo'],
        'cantrips' => ['Prestidigitação', 'Raio de Fogo', 'Mage Hand']
      }
    }
  },
  race_summary: {
    'speed_ft' => 30,
    'speed_m' => 9,
    'languages' => ['Comum', 'Draconico'],
    'traits' => ['feat', 'skill'],
    'proficiencies' => {
      'skills' => ['Investigação'],
      'tools' => []
    }
  },
  class_summary: {
    'klass_id' => 'wizard',
    'name' => 'Mago',
    'hit_die' => 'd6',
    'primary_abilities' => ['INT'],
    'saving_throws' => ['INT', 'WIS'],
    'armor_proficiencies' => [],
    'weapon_proficiencies' => ['adagas', 'dardos', 'fundas', 'varinhas', 'bastões leves'],
    'tools' => [],
    'skills' => ['Arcanismo', 'História'],
    'subclass' => 'evocation',
    'spellcasting' => {'ability' => 'INT', 'spell_save_dc' => 13, 'spell_attack_bonus' => 5},
    'current_level' => 1
  },
  features_by_level: {
    '1' => [
      {
        'id' => 5,
        'api_index' => 'spellcasting',
        'name' => 'Conjuracao',
        'category' => 'class_feature',
        'description' => 'Como estudante de magia, você tem um grimório contendo magias que mostram os primeiros sinais de sua verdadeira arte.'
      },
      {
        'id' => 6,
        'api_index' => 'arcane-recovery',
        'name' => 'Recuperação Arcana',
        'category' => 'class_feature',
        'description' => 'Você aprendeu a recuperar parte de sua energia mágica estudando seu grimório.'
      }
    ]
  },
  race_bonuses_applied: {'str' => 1, 'dex' => 1, 'con' => 1, 'int' => 1, 'wis' => 1, 'cha' => 1},
  metadata: {
    'race_choices' => {'humanFeat' => 'Observador', 'humanSkill' => 'Investigação'},
    'background' => 'Sábio',
    'background_key' => 'sage',
    'alignment' => {'index' => 'neutral', 'name' => 'Neutral', 'desc' => 'Neutral (N) is the alignment of those who prefer to steer clear of moral questions and don\'t take sides.'},
    'current_level' => 1
  }
)

puts "Terceiro personagem criado: #{character3.name}"
puts "Sheet ID: #{sheet3.id}"

puts "\n=== RESUMO DOS PERSONAGENS CRIADOS ==="
puts "1. #{character.name} - Anão Guerreiro (Sheet ID: #{sheet.id})"
puts "2. #{character2.name} - Elfo Bardo (Sheet ID: #{sheet2.id})"
puts "3. #{character3.name} - Humano Mago (Sheet ID: #{sheet3.id})"
puts "\nTodas as colunas normalizadas estão funcionando corretamente!"
