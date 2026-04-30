class RaceRules
  CACHE_KEY = 'race_rules_v1'.freeze
  YAML_PATH = Rails.root.join('config', 'race_rules.yml')
  CACHE_TTL = 12.hours

  def self.rules
    bundle[:races]
  end

  def self.trait_definitions
    bundle[:trait_definitions]
  end

  def self.reload!
    Rails.cache.delete(CACHE_KEY)
    data = load_rules
    Rails.cache.write(CACHE_KEY, data, expires_in: CACHE_TTL)
    data
  end

  def self.find(id)
    return nil if id.blank?

    key = id.to_s
    data = rules
    data[key.to_sym] || data[key]
  end

  # api_index legado ou SRD que não bate com a chave em `subraces:` do YAML (ex.: hill_dwarf → hill).
  # Inclui slugs PT-BR vindos de `SubRace#name.parameterize` (ex.: anao_da_colina → hill) — sem
  # isso `RacialHpBonus.per_level_for_sheet` falha no LevelUpService e só o init_hp soma +1 PV.
  SUBRACE_KEY_ALIASES = {
    %w[dwarf hill_dwarf] => 'hill',
    %w[dwarf mountain_dwarf] => 'mountain',
    %w[dwarf anao_da_colina] => 'hill',
    %w[dwarf anao-da-colina] => 'hill',
    %w[dwarf colina] => 'hill',
    %w[dwarf anao_da_montanha] => 'mountain',
    %w[dwarf anao-da-montanha] => 'mountain',
    %w[dwarf montanha] => 'mountain',
    %w[elf wood_elf] => 'wood',
    %w[elf high_elf] => 'high',
    %w[elf elfo_da_floresta] => 'wood',
    %w[elf floresta] => 'wood',
    %w[elf alto_elfo] => 'high',
    %w[elf alto] => 'high',
    %w[gnome forest_gnome] => 'forest',
    %w[gnome rock_gnome] => 'rock',
    %w[halfling lightfoot_halfling] => 'lightfoot',
    %w[halfling stout_halfling] => 'stout',
  }.freeze

  RACE_KEY_ALIASES = {
    'anao' => 'dwarf',
    'elfo' => 'elf',
    'halfling' => 'halfling',
    'humano' => 'human',
    'draconato' => 'dragonborn',
    'gnomo' => 'gnome',
    'meio_elfo' => 'half_elf',
    'meio-elfo' => 'half_elf',
    'meio_orc' => 'half_orc',
    'meio-orc' => 'half_orc',
    'tiefling' => 'tiefling',
    'tabaxi' => 'tabaxi',
    'aarakocra' => 'aarakocra',
    'centauro' => 'centaur',
  }.freeze

  def self.normalize_race_key(race_id)
    rk = race_id.to_s.strip
    RACE_KEY_ALIASES[rk] || rk
  end

  # @return [String, nil] chave canónica presente em `race[:subraces]`, ou o valor original se já casar
  def self.canonical_subrace_key(race_id, sub_key)
    return nil if sub_key.blank?

    sk = sub_key.to_s.strip
    nr = normalize_race_key(race_id)
    race = find(nr)
    return sk if race.blank?

    subraces = race[:subraces] || {}
    return sk if subraces[sk.to_sym].present? || subraces[sk].present?

    mapped = SUBRACE_KEY_ALIASES[[nr, sk]]
    if mapped.present? && (subraces[mapped.to_sym].present? || subraces[mapped].present?)
      return mapped
    end

    sk
  end

  # Very light merger of base race + subrace (no full validation here)
  def self.apply(selection)
    raw_race = selection[:race_id]
    raise ArgumentError, 'race not found' if raw_race.blank?

    rid = normalize_race_key(raw_race)
    race = find(rid)
    raise ArgumentError, 'race not found' unless race

    subraces = race[:subraces] || {}
    sub_key = selection[:subrace_id]
    canonical = sub_key.present? ? canonical_subrace_key(rid, sub_key) : nil
    sub = if canonical.present?
            subraces[canonical.to_sym] || subraces[canonical.to_s]
          end

    merged = deep_merge(race.deep_dup, (sub || {}).deep_dup)

    # Languages
    langs = Array(merged.dig(:languages, :always)).dup
    if merged.dig(:languages, :choiceCount).to_i > 0
      picks = Array(selection.dig(:choices, :extraLanguages))
      langs.concat(picks.first(merged.dig(:languages, :choiceCount).to_i))
    end

    # Extract innate spells from traits
    innate_spells = extract_innate_spells_from_traits(merged[:traits] || [])

    {
      race_id: selection[:race_id],
      subrace_id: selection[:subrace_id],
      ability: merged[:ability],
      speed: merged[:speed],
      darkvision: merged[:darkvision],
      languages: langs.uniq,
      proficiencies: merged[:proficiencies] || {},
      traits: merged[:traits] || [],
      innate_spells: innate_spells,
      requires: merged[:requires] || []
    }
  end

  # Extract innate spells from trait definitions
  def self.extract_innate_spells_from_traits(traits)
    result = []
    trait_defs = trait_definitions

    Array(traits).each do |trait_ref|
      trait_key = trait_ref.is_a?(Hash) ? (trait_ref[:key] || trait_ref['key']) : trait_ref
      next unless trait_key

      trait_def = trait_defs[trait_key.to_sym] || trait_defs[trait_key.to_s]
      next unless trait_def

      spells = trait_def.dig(:grants, :spells) || trait_def.dig('grants', 'spells')
      next unless spells.present?

      Array(spells).each do |spell_entry|
        spell_name = spell_entry[:spell] || spell_entry['spell']
        # minimum_level is the character level required to unlock the spell
        char_level_req = (spell_entry[:minimum_level] || spell_entry['minimum_level'] || 1).to_i
        ability = (spell_entry[:ability] || spell_entry['ability'] || 'CHA').to_s.upcase
        usage = spell_entry[:usage] || spell_entry['usage']
        
        # Convert usage to uses_per_rest format
        uses = case usage.to_s.downcase
               when 'at_will', 'atwill' then nil
               when /long.*rest|lr|longo|per_long_rest/i then 'LR'
               when /short.*rest|sr|curto|per_short_rest/i then 'SR'
               else nil
               end

        result << {
          name: spell_name,
          unlocked_at_level: char_level_req,
          ability: ability,
          uses: uses
        }
      end
    end

    result
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

  def self.bundle
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { load_rules }
  end

  def self.load_rules
    return { races: {}, trait_definitions: {} } unless YAML_PATH.exist?

    raw = YAML.safe_load(YAML_PATH.read, aliases: true) || {}
    raw = raw.deep_symbolize_keys
    trait_defs = raw.delete(:trait_definitions) || {}

    { races: raw, trait_definitions: trait_defs }
  rescue => e
    Rails.logger.warn("RaceRules: falha ao carregar #{YAML_PATH}: #{e.message}") if defined?(Rails.logger)
    { races: {}, trait_definitions: {} }
  end
end
