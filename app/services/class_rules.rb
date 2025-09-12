class ClassRules
  INSTRUMENTS = %w[gaida tambor salterio flauta alaude lira trompa flauta_de_pan charamela violino].freeze
  FIGHTING_STYLES = [
    'Defesa', 'Arquearia', 'Duelos', 'Combate com Duas Armas',
    'Proteção', 'Grande Arma'
  ].freeze

  SKILLS_ALL = [
    'Acrobacia','Arcanismo','Atletismo','Atuação','Enganação','Furtividade','História','Intimidação',
    'Intuição','Investigação','Lidar com Animais','Medicina','Natureza','Percepção',
    'Persuasão','Prestidigitação','Religião','Sobrevivência'
  ].freeze

  def self.rules
    Rails.cache.fetch('class_rules_v1', expires_in: 12.hours) { CLASS_RULES }
  end

  def self.dictionaries
    {
      instruments: INSTRUMENTS,
      fighting_styles: FIGHTING_STYLES,
      skills_all: SKILLS_ALL,
      invocations_core: [
        'Agonizing Blast', 'Armor of Shadows', 'Devil\'s Sight', 'Fiendish Vigor',
        'Mask of Many Faces', 'Misty Visions', 'Eldritch Sight', 'Beast Speech',
        'Book of Ancient Secrets'
      ],
      # Ranger specific dictionaries
      ranger_favored_enemy_types: [
        'Aberrações','Bestas','Celestiais','Constructos','Dragões','Elementais','Fadas',
        'Infernais','Gigantes','Monstruosidades','Lodos','Plantas','Mortos‑vivos',
        'Humanoides (2 raças)'
      ],
      ranger_favored_terrain_types: [
        'Ártico','Costeiro','Deserto','Floresta','Pradaria','Montanha','Pântano','Subterrâneo'
      ],
      ranger_humanoid_races: [
        'Humano','Elfo','Anão','Halfling','Gnomo','Orc','Goblinoide','Gnoll','Kobold','Hobgoblin','Bugbear','Tritão','Draconato'
      ]
    }
  end

  def self.find(id)
    rules[id.to_s]
  end

  # Aplica picks do usuário e retorna um resumo para preview/persistência
  # selection: { klass_id:, level:, picks: {...}, skills_selected: [], tools_selected: [], instruments_selected: [] }
  def self.apply(selection)
    rule = find(selection[:klass_id])
    raise ArgumentError, 'class not found' unless rule
    level = selection[:level].to_i.nonzero? || 1
    picks = selection[:picks] || {}

    # Proficiencias básicas
    armor = Array(rule[:armor_proficiencies])
    weapons = Array(rule[:weapon_proficiencies])
    tools = Array(rule[:tool_proficiencies])

    # Instrumentos (Ex.: Bardo)
    if rule.dig(:tool_proficiencies, :instruments, :choose)
      chosen = Array(selection[:instruments_selected]).map { |x| (x.is_a?(Hash) ? x[:name] : x).to_s }
      tools << { instruments: chosen.first(rule[:tool_proficiencies][:instruments][:choose].to_i) }
    end

    # Perícias da classe
    class_skills = if rule.dig(:skill_proficiencies, :options) == :any
                     SKILLS_ALL
                   else
                     Array(rule.dig(:skill_proficiencies, :options))
                   end
    skills_chosen = Array(selection[:skills_selected]).map { |x| (x.is_a?(Hash) ? x[:name] : x).to_s }
    skills = skills_chosen.first(rule.dig(:skill_proficiencies, :choose).to_i)

    # Escolhas obrigatórias por nível (ex.: Estilo de Luta)
    required = (rule[:required_choices_at_level] || {}).select { |lvl, _| lvl.to_i <= level }
    required_summary = {}
    required.each do |key_level, h|
      h.each do |key, conf|
        chosen = picks[key] || picks[key.to_s]
        if conf[:choose].to_i > 1
          chosen = Array(chosen).first(conf[:choose].to_i)
        end
        required_summary[key] = chosen
      end
    end

    # Subclasse se elegível
    subclass = nil
    if rule.dig(:subclass, :choose_level).to_i > 0 && level >= rule[:subclass][:choose_level].to_i
      sc_id = picks[:subclass_id] || picks['subclass_id']
      subclass = rule.dig(:subclass, :options, sc_id.to_sym) if sc_id
    end

    {
      klass_id: rule[:id],
      name: rule[:name],
      hit_die: rule[:hit_die],
      primary_abilities: rule[:primary_abilities],
      saving_throws: rule[:saving_throws],
      armor_proficiencies: armor,
      weapon_proficiencies: weapons,
      tool_proficiencies: tools,
      skill_proficiencies_available: class_skills,
      skills_selected: skills,
      features_level1: rule[:features_level1],
      subclass: subclass,
      subclass_choose_level: rule.dig(:subclass, :choose_level),
      spellcasting: rule[:spellcasting],
      required_choices: required_summary
    }
  end

  CLASS_RULES = {
    barbarian: {
      id: 'barbarian', name: 'Bárbaro', hit_die: 'd12',
      primary_abilities: %w[STR CON], saving_throws: %w[STR CON],
      armor_proficiencies: %w[leve média escudos],
      weapon_proficiencies: ['armas simples','armas marciais'],
      tool_proficiencies: [],
      skill_proficiencies: { choose: 2, options: ['Lidar com Animais','Atletismo','Intimidação','Natureza','Percepção','Sobrevivência'] },
      features_level1: ['Fúria','Defesa sem Armadura'],
      subclass: { choose_level: 3, options: { berserker: { id: 'berserker', name: 'Caminho do Berserker' }, totem: { id: 'totem', name: 'Caminho do Totem' } } },
      resources: { rage: { uses: 'escala com nível', recharge: 'LR' } },
      required_choices_at_level: {}
    },

    bard: {
      id: 'bard', name: 'Bardo', hit_die: 'd8',
      primary_abilities: %w[CHA], saving_throws: %w[DEX CHA],
      armor_proficiencies: %w[leve],
      weapon_proficiencies: ['armas simples','bestas de mão','espadas longas','rapieiras','espadas curtas'],
      tool_proficiencies: { instruments: { choose: 3, choices: INSTRUMENTS } },
      skill_proficiencies: { choose: 3, options: :any },
      features_level1: ['Inspiração Bárdica (d6)','Conjuração'],
      subclass: { choose_level: 3, options: { lore: { id: 'lore', name: 'Colégio do Conhecimento' }, valor: { id: 'valor', name: 'Colégio do Valor' } } },
      spellcasting: {
        type: 'full', casting_ability: 'CHA', preparation: 'known',
        cantrips_known_at_1: 2, spells_known_at_1: 4,
        ritual: 'if_known', focus: 'arcane_focus', list: 'bard'
      },
      required_choices_at_level: {}
    },

    cleric: {
      id: 'cleric', name: 'Clérigo', hit_die: 'd8',
      primary_abilities: %w[WIS], saving_throws: %w[WIS CHA],
      armor_proficiencies: %w[leve média escudos],
      weapon_proficiencies: ['armas simples'],
      tool_proficiencies: [],
      skill_proficiencies: { choose: 2, options: ['História','Intuição','Medicina','Persuasão','Religião'] },
      features_level1: ['Conjuração','Domínio Divino'],
      subclass: {
        choose_level: 1,
        options: {
          life: { id: 'life', name: 'Vida' }, light: { id: 'light', name: 'Luz' }, knowledge: { id: 'knowledge', name: 'Conhecimento' },
          nature: { id: 'nature', name: 'Natureza' }, tempest: { id: 'tempest', name: 'Tempestade' }, trickery: { id: 'trickery', name: 'Trapaça' }, war: { id: 'war', name: 'Guerra' }
        }
      },
      spellcasting: {
        type: 'full', casting_ability: 'WIS', preparation: 'prepared',
        cantrips_known_at_1: 3, spells_known_at_1: nil,
        ritual: 'if_prepared', focus: 'holy_symbol', list: 'cleric'
      },
      required_choices_at_level: {}
    },

    druid: {
      id: 'druid', name: 'Druida', hit_die: 'd8',
      primary_abilities: %w[WIS], saving_throws: %w[INT WIS],
      armor_proficiencies: %w[leve média escudos],
      weapon_proficiencies: ['clavas','adagas','dardos','azagaias','maças','bordões','cimitarra','foices','fundas','lanças'],
      tool_proficiencies: ['Kit de Herbalismo'],
      skill_proficiencies: { choose: 2, options: ['Arcanismo','Lidar com Animais','Intuição','Medicina','Natureza','Percepção','Religião','Sobrevivência'] },
      features_level1: ['Conjuração','Druídico'],
      subclass: { choose_level: 2, options: { land: { id: 'land', name: 'Círculo da Terra' }, moon: { id: 'moon', name: 'Círculo da Lua' } } },
      spellcasting: {
        type: 'full', casting_ability: 'WIS', preparation: 'prepared',
        cantrips_known_at_1: 2, spells_known_at_1: nil,
        ritual: 'if_prepared', focus: 'druidic_focus', list: 'druid'
      },
      required_choices_at_level: {}
    },

    fighter: {
      id: 'fighter', name: 'Guerreiro', hit_die: 'd10',
      primary_abilities: %w[STR DEX CON], saving_throws: %w[STR CON],
      armor_proficiencies: %w[leve média pesada escudos],
      weapon_proficiencies: ['armas simples','armas marciais'],
      tool_proficiencies: [],
      skill_proficiencies: { choose: 2, options: ['Acrobacia','Lidar com Animais','Atletismo','História','Intuição','Intimidação','Percepção','Sobrevivência'] },
      features_level1: ['Estilo de Luta (escolha 1)','Segundo Fôlego'],
      subclass: {
        choose_level: 3,
        options: {
          champion: { id: 'champion', name: 'Campeão' },
          battlemaster: { id: 'battlemaster', name: 'Mestre de Batalha' },
          eldritch_knight: { id: 'eldritch_knight', name: 'Cavaleiro Arcano', grants: { spellcasting: { type: 'third', casting_ability: 'INT', preparation: 'known', cantrips_known_at_1: 0, spells_known_at_1: 0, ritual: false, focus: 'arcane_focus', list: 'wizard', school_bias: %w[Abjuração Evocação] } } }
        }
      },
      required_choices_at_level: { 1 => { fighting_style: { choose: 1, options: FIGHTING_STYLES } } }
    },

    monk: {
      id: 'monk', name: 'Monge', hit_die: 'd8',
      primary_abilities: %w[DEX WIS], saving_throws: %w[STR DEX],
      armor_proficiencies: [],
      weapon_proficiencies: ['armas simples','espadas curtas'],
      tool_proficiencies: { choose: 1, options: ['Ferramentas de artesão (escolha 1)','Instrumento musical (escolha 1)'] },
      skill_proficiencies: { choose: 2, options: ['Acrobacia','Atletismo','História','Intuição','Religião','Furtividade'] },
      features_level1: ['Defesa sem Armadura','Artes Marciais'],
      subclass: { choose_level: 3, options: { open_hand: { id: 'open_hand', name: 'Caminho da Mão Aberta' }, shadow: { id: 'shadow', name: 'Caminho da Sombra' }, four_elements: { id: 'four_elements', name: 'Caminho dos Quatro Elementos' } } },
      required_choices_at_level: {}
    },

    paladin: {
      id: 'paladin', name: 'Paladino', hit_die: 'd10',
      primary_abilities: %w[STR CHA], saving_throws: %w[WIS CHA],
      armor_proficiencies: %w[leve média pesada escudos],
      weapon_proficiencies: ['armas simples','armas marciais'],
      tool_proficiencies: [],
      skill_proficiencies: { choose: 2, options: ['Atletismo','Intuição','Intimidação','Medicina','Persuasão','Religião'] },
      features_level1: ['Sentido Divino','Imposição das Mãos'],
      subclass: { choose_level: 3, options: { devotion: { id: 'devotion', name: 'Juramento da Devoção' }, ancients: { id: 'ancients', name: 'Juramento dos Anciões' }, vengeance: { id: 'vengeance', name: 'Juramento da Vingança' } } },
      spellcasting: { type: 'half', casting_ability: 'CHA', preparation: 'prepared', cantrips_known_at_1: 0, spells_known_at_1: nil, ritual: 'if_prepared', focus: 'holy_symbol', list: 'paladin' },
      required_choices_at_level: { 2 => { fighting_style: { choose: 1, options: FIGHTING_STYLES } } }
    },

    ranger: {
      id: 'ranger', name: 'Patrulheiro', hit_die: 'd10',
      primary_abilities: %w[DEX WIS], saving_throws: %w[STR DEX],
      armor_proficiencies: %w[leve média escudos],
      weapon_proficiencies: ['armas simples','armas marciais'],
      tool_proficiencies: [],
      skill_proficiencies: { choose: 3, options: ['Lidar com Animais','Atletismo','Intuição','Investigação','Natureza','Percepção','Furtividade','Sobrevivência'] },
      features_level1: ['Inimigo Favorito','Explorador Nato'],
      subclass: { choose_level: 3, options: { hunter: { id: 'hunter', name: 'Caçador' }, beast_master: { id: 'beast_master', name: 'Mestre das Feras' } } },
      spellcasting: { type: 'half', casting_ability: 'WIS', preparation: 'known', cantrips_known_at_1: 0, spells_known_at_1: 0, ritual: false, focus: nil, list: 'ranger' },
      required_choices_at_level: {
        1 => {
          favored_enemy: { choose: 1, options: :ranger_favored_enemy_types },
          favored_terrain: { choose: 1, options: :ranger_favored_terrain_types }
        },
        2 => { fighting_style: { choose: 1, options: FIGHTING_STYLES } },
        6 => {
          favored_enemy: { choose: 1, options: :ranger_favored_enemy_types },
          favored_terrain: { choose: 1, options: :ranger_favored_terrain_types }
        },
        10 => { favored_terrain: { choose: 1, options: :ranger_favored_terrain_types } },
        14 => { favored_enemy: { choose: 1, options: :ranger_favored_enemy_types } }
      }
    },

    rogue: {
      id: 'rogue', name: 'Ladino', hit_die: 'd8',
      primary_abilities: %w[DEX], saving_throws: %w[DEX INT],
      armor_proficiencies: %w[leve],
      weapon_proficiencies: ['armas simples','bestas de mão','espadas longas','rapieiras','espadas curtas'],
      tool_proficiencies: ['Ferramentas de Ladrão'],
      skill_proficiencies: { choose: 4, options: ['Acrobacia','Atletismo','Enganação','Intuição','Intimidação','Investigação','Percepção','Atuação','Persuasão','Prestidigitação','Furtividade'] },
      features_level1: ['Perícia (escolha 2)','Ataque Furtivo','Gíria de Ladrão'],
      subclass: { choose_level: 3, options: { thief: { id: 'thief', name: 'Ladrão' }, assassin: { id: 'assassin', name: 'Assassino' }, arcane_trickster: { id: 'arcane_trickster', name: 'Trapaceiro Arcano', grants: { spellcasting: { type: 'third', casting_ability: 'INT', preparation: 'known', cantrips_known_at_1: 0, spells_known_at_1: 0, ritual: false, focus: 'arcane_focus', list: 'wizard', school_bias: %w[Ilusão Encantamento] } } } } },
      required_choices_at_level: { 1 => { expertise_skills: { choose: 2, options: :selected_from_class_skills } } }
    },

    sorcerer: {
      id: 'sorcerer', name: 'Feiticeiro', hit_die: 'd6',
      primary_abilities: %w[CHA], saving_throws: %w[CON CHA],
      armor_proficiencies: [], weapon_proficiencies: ['adagas','dardos','fundas','bordões','bestas leves'],
      tool_proficiencies: [],
      skill_proficiencies: { choose: 2, options: ['Arcanismo','Enganação','Intuição','Intimidação','Persuasão','Religião'] },
      features_level1: ['Conjuração','Origem Feiticeira'],
      subclass: { choose_level: 1, options: { draconic: { id: 'draconic', name: 'Linhagem Dracônica' }, wild: { id: 'wild', name: 'Magia Selvagem' } } },
      spellcasting: { type: 'full', casting_ability: 'CHA', preparation: 'known', cantrips_known_at_1: 4, spells_known_at_1: 2, ritual: false, focus: 'arcane_focus', list: 'sorcerer' },
      required_choices_at_level: { 3 => { metamagic: { choose: 2, options: ['Acelerar Magia','Alcançar Magia','Expandir Magia','Estender Magia','Suturar Magia','Potencializar Magia','Sutilizar Magia','Transmutar Magia'] } } }
    },

    warlock: {
      id: 'warlock', name: 'Bruxo', hit_die: 'd8',
      primary_abilities: %w[CHA], saving_throws: %w[WIS CHA],
      armor_proficiencies: %w[leve], weapon_proficiencies: ['armas simples'], tool_proficiencies: [],
      skill_proficiencies: { choose: 2, options: ['Arcanismo','Enganação','História','Intimidação','Investigação','Natureza','Religião'] },
      features_level1: ['Patrono Sobrenatural','Magia de Pacto'],
      subclass: { choose_level: 1, options: { fiend: { id: 'fiend', name: 'O Ínfero' }, archfey: { id: 'archfey', name: 'A Rainha/Príncipe das Fadas' }, great_old_one: { id: 'goo', name: 'O Grande Antigo' } } },
      spellcasting: { type: 'pact', casting_ability: 'CHA', preparation: 'known', cantrips_known_at_1: 2, spells_known_at_1: 2, ritual: false, focus: 'arcane_focus', list: 'warlock' },
      required_choices_at_level: {
        2 => { invocations: { choose: 2, options: :invocations_core } },
        3 => { pact_boon: { choose: 1, options: ['Pacto da Lâmina','Pacto da Corrente','Pacto do Tomo'] } }
      }
    },

    wizard: {
      id: 'wizard', name: 'Mago', hit_die: 'd6',
      primary_abilities: %w[INT], saving_throws: %w[INT WIS],
      armor_proficiencies: [], weapon_proficiencies: ['adagas','dardos','fundas','bordões','bestas leves'], tool_proficiencies: [],
      skill_proficiencies: { choose: 2, options: ['Arcanismo','História','Intuição','Investigação','Medicina','Religião'] },
      features_level1: ['Conjuração','Recuperação Arcana'],
      subclass: { choose_level: 2, options: { abjuration: { id: 'abjuration', name: 'Abjuração' }, conjuration: { id: 'conjuration', name: 'Conjuração' }, divination: { id: 'divination', name: 'Adivinhação' }, enchantment: { id: 'enchantment', name: 'Encantamento' }, evocation: { id: 'evocation', name: 'Evocação' }, illusion: { id: 'illusion', name: 'Ilusão' }, necromancy: { id: 'necromancy', name: 'Necromancia' }, transmutation: { id: 'transmutation', name: 'Transmutação' } } },
      spellcasting: { type: 'full', casting_ability: 'INT', preparation: 'prepared', cantrips_known_at_1: 3, spells_known_at_1: 6, ritual: 'spellbook', focus: 'arcane_focus', list: 'wizard' },
      required_choices_at_level: {}
    }
  }.with_indifferent_access.freeze
end
