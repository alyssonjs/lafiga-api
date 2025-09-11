class RaceRules
  # Static SRD-friendly race rules used by the public API and UI wizard
  # Keep controller thin; centralize data + helpers here.

  def self.rules
    Rails.cache.fetch('race_rules_v1', expires_in: 12.hours) { RULES }
  end

  def self.find(id)
    rules[id.to_s]
  end

  # Very light merger of base race + subrace (no full validation here)
  def self.apply(selection)
    race = find(selection[:race_id])
    raise ArgumentError, 'race not found' unless race
    sub = selection[:subrace_id].present? ? (race[:subraces] || {})[selection[:subrace_id].to_sym] : nil
    merged = deep_merge(race.dup, sub || {})

    # Languages
    langs = Array(merged.dig(:languages, :always)).dup
    if merged.dig(:languages, :choiceCount).to_i > 0
      picks = Array(selection.dig(:choices, :extraLanguages))
      langs.concat(picks.first(merged.dig(:languages, :choiceCount).to_i))
    end

    {
      race_id: selection[:race_id],
      subrace_id: selection[:subrace_id],
      ability: merged[:ability],
      speed: merged[:speed],
      darkvision: merged[:darkvision],
      languages: langs.uniq,
      proficiencies: merged[:proficiencies] || {},
      traits: merged[:traits] || [],
      innate_spells: merged[:innateSpells] || [],
      requires: merged[:requires] || []
    }
  end

  def self.deep_merge(a, b)
    return a unless b.present?
    a.merge(b) do |_k, v1, v2|
      case v1
      when Hash
        deep_merge(v1, v2 || {})
      when Array
        Array(v1) + Array(v2)
      else
        v2.nil? ? v1 : v2
      end
    end
  end

  # Data ported from Api::V1::Public::RaceRulesController (kept in Ruby Hash)
  RULES = {
    dwarf: {
      id: 'dwarf', name: 'Anão', speed: 25,
      ability: { type: 'fixed', increases: [{ ability: 'CON', amount: 2 }] },
      darkvision: { range: 60 },
      languages: { always: ['Comum', 'Anão'], choiceCount: 0 },
      proficiencies: { weapons: ['machado de batalha', 'machadinha', 'martelo leve', 'martelo de guerra'], tools: { choiceCount: 1, choices: ['Ferramentas de ferreiro', 'Suprimentos de cervejeiro', 'Ferramentas de pedreiro'] } },
      traits: [{ key: 'dwarven_resilience' }, { key: 'stonecunning' }, { key: 'speed_not_reduced_by_heavy_armor' }, { key: 'darkvision', range: 60 }],
      subraces: {
        hill: { id: 'hill', name: 'Anão da Colina', ability: { type: 'fixed', increases: [{ ability: 'WIS', amount: 1 }] }, traits: [{ key: 'dwarven_toughness' }] },
        mountain: { id: 'mountain', name: 'Anão da Montanha', ability: { type: 'fixed', increases: [{ ability: 'STR', amount: 2 }] }, proficiencies: { armor: ['leve', 'média'] } }
      },
      requires: ['dwarfTool']
    },
    elf: {
      id: 'elf', name: 'Elfo', speed: 30,
      ability: { type: 'fixed', increases: [{ ability: 'DEX', amount: 2 }] },
      darkvision: { range: 60 },
      languages: { always: ['Comum', 'Élfico'], choiceCount: 0 },
      proficiencies: { skills: { fixed: ['Percepção'] } },
      traits: [{ key: 'fey_ancestry' }, { key: 'trance' }, { key: 'keen_senses' }, { key: 'darkvision', range: 60 }],
      subraces: {
        # Alto Elfo: idioma extra e um truque (cantrip)
        high: { id: 'high', name: 'Alto Elfo', ability: { type: 'fixed', increases: [{ ability: 'INT', amount: 1 }] },
                proficiencies: { weapons: ['espada longa', 'espada curta', 'arco curto', 'arco longo'] },
                languages: { choiceCount: 1, choiceList: ['Anão','Halfling','Dracônico','Gnômico','Orc','Infernal'] },
                requires: ['highElfCantrip', 'highElfExtraLanguage'] },
        wood: { id: 'wood', name: 'Elfo da Floresta', ability: { type: 'fixed', increases: [{ ability: 'WIS', amount: 1 }] }, speed: 35, proficiencies: { weapons: ['espada longa', 'espada curta', 'arco curto', 'arco longo'] }, traits: [{ key: 'fleet_of_foot' }, { key: 'mask_of_the_wild' }] },
        drow: { id: 'drow', name: 'Elfo Negro (Drow)', ability: { type: 'fixed', increases: [{ ability: 'CHA', amount: 1 }] }, traits: [{ key: 'superior_darkvision', range: 120 }, { key: 'sunlight_sensitivity' }], proficiencies: { weapons: ['rapieira', 'espada curta', 'besta de mão'] }, innateSpells: [ { level: 1, spells: ['Luzes Dançantes'], ability: 'CHA' }, { level: 3, spells: ['Fogo das Fadas'], ability: 'CHA', uses: 'LR' }, { level: 5, spells: ['Escuridão'], ability: 'CHA', uses: 'LR' } ] }
      },
      # Requisitos específicos estão declarados nas sub-raças (ex.: Alto Elfo)
    },
    human: {
      id: 'human', name: 'Humano', speed: 30,
      ability: { type: 'fixed', increases: [ { ability: 'STR', amount: 1 }, { ability: 'DEX', amount: 1 }, { ability: 'CON', amount: 1 }, { ability: 'INT', amount: 1 }, { ability: 'WIS', amount: 1 }, { ability: 'CHA', amount: 1 } ] },
      darkvision: nil,
      languages: { always: ['Comum'], choiceCount: 1, choiceList: ['Anão','Élfico','Halfling','Dracônico','Gnômico','Orc','Infernal'] },
      traits: [],
      subraces: { variant: { id: 'variant', name: 'Humano Variante', ability: { type: 'variantHuman', chooseAbilities: { count: 2, amount: 1 }, skillChoices: 1, feat: true } } }
    },
    dragonborn: { id: 'dragonborn', name: 'Draconato', speed: 30, ability: { type: 'fixed', increases: [{ ability: 'STR', amount: 2 }, { ability: 'CHA', amount: 1 }] }, darkvision: nil, languages: { always: ['Comum','Dracônico'], choiceCount: 0 }, traits: [], requires: ['draconicAncestry'] },
    gnome: { id: 'gnome', name: 'Gnomo', speed: 25, ability: { type: 'fixed', increases: [{ ability: 'INT', amount: 2 }] }, darkvision: { range: 60 }, languages: { always: ['Comum','Gnômico'], choiceCount: 0 }, traits: [{ key: 'gnome_cunning' }, { key: 'darkvision', range: 60 }], subraces: { forest: { id: 'forest', name: 'Gnomo da Floresta', ability: { type: 'fixed', increases: [{ ability: 'DEX', amount: 1 }] }, innateSpells: [{ level: 1, spells: ['Ilusão Menor'], ability: 'INT' }], traits: [{ key: 'speak_with_small_beasts' }] }, rock: { id: 'rock', name: 'Gnomo das Rochas', ability: { type: 'fixed', increases: [{ ability: 'CON', amount: 1 }] }, traits: [{ key: 'artificers_lore' }, { key: 'tinker' }] } } },
    half_elf: { id: 'half_elf', name: 'Meio-Elfo', speed: 30, ability: { type: 'halfElf', fixed: [{ ability: 'CHA', amount: 2 }], choose: { count: 2, amount: 1 } }, darkvision: { range: 60 }, languages: { always: ['Comum','Élfico'], choiceCount: 1, choiceList: ['Anão','Halfling','Dracônico','Gnômico','Orc','Infernal'] }, proficiencies: { skills: { choiceCount: 2, choices: ['Acrobacia','Arcanismo','Atletismo','Atuação','Enganação','Furtividade','História','Intimidação','Intuição','Investigação','Lidar com Animais','Medicina','Natureza','Percepção','Persuasão','Religião','Sobrevivência'] } }, traits: [{ key: 'fey_ancestry' }, { key: 'darkvision', range: 60 }] },
    half_orc: { id: 'half_orc', name: 'Meio-Orc', speed: 30, ability: { type: 'fixed', increases: [{ ability: 'STR', amount: 2 }, { ability: 'CON', amount: 1 }] }, darkvision: { range: 60 }, languages: { always: ['Comum','Orc'], choiceCount: 0 }, proficiencies: { skills: { fixed: ['Intimidação'] } }, traits: [{ key: 'relentless_endurance' }, { key: 'savage_attacks' }, { key: 'darkvision', range: 60 }] },
    halfling: { id: 'halfling', name: 'Halfling', speed: 25, ability: { type: 'fixed', increases: [{ ability: 'DEX', amount: 2 }] }, darkvision: nil, languages: { always: ['Comum','Halfling'], choiceCount: 0 }, traits: [{ key: 'lucky' }, { key: 'brave' }, { key: 'halfling_nimbleness' }], subraces: { lightfoot: { id: 'lightfoot', name: 'Pés Leves', ability: { type: 'fixed', increases: [{ ability: 'CHA', amount: 1 }] }, traits: [{ key: 'naturally_stealthy' }] }, stout: { id: 'stout', name: 'Robusto', ability: { type: 'fixed', increases: [{ ability: 'CON', amount: 1 }] }, traits: [{ key: 'dwarven_resilience' }] } } },
    tiefling: { id: 'tiefling', name: 'Tiefling', speed: 30, ability: { type: 'fixed', increases: [{ ability: 'CHA', amount: 2 }, { ability: 'INT', amount: 1 }] }, darkvision: { range: 60 }, languages: { always: ['Comum','Infernal'], choiceCount: 0 }, traits: [{ key: 'hellish_resistance' }, { key: 'darkvision', range: 60 }], innateSpells: [ { level: 1, spells: ['Taumaturgia'], ability: 'CHA' }, { level: 3, spells: ['Repreensão Infernal (nível 2)'], ability: 'CHA', uses: 'LR' }, { level: 5, spells: ['Escuridão'], ability: 'CHA', uses: 'LR' } ] }
  }.with_indifferent_access.freeze
end
