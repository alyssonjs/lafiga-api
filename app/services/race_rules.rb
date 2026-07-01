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
  # Inclui:
  #   - slugs SRD/legado (`hill_dwarf` → `hill`)
  #   - slugs PT-BR vindos de `SubRace#name.parameterize` (`anao_da_colina` → `hill`)
  #   - slugs PT-BR com hífen e variações com acento (`falcônicos` → `falconicos`)
  #
  # Esta tabela é a **única fonte de tradução** consumida por
  # `canonical_subrace_key`. Antes da consolidação, `RaceProfileService` mantinha
  # um `sub_map_by_race` paralelo, com risco de divergência ao adicionar raças.
  SUBRACE_KEY_ALIASES = {
    # --- Anão / Dwarf ---
    %w[dwarf hill_dwarf] => 'hill',
    %w[dwarf mountain_dwarf] => 'mountain',
    %w[dwarf anao_da_colina] => 'hill',
    %w[dwarf anao-da-colina] => 'hill',
    %w[dwarf colina] => 'hill',
    %w[dwarf anao_da_montanha] => 'mountain',
    %w[dwarf anao-da-montanha] => 'mountain',
    %w[dwarf montanha] => 'mountain',
    # --- Elfo / Elf ---
    %w[elf wood_elf] => 'wood',
    %w[elf high_elf] => 'high',
    %w[elf elfo_da_floresta] => 'wood',
    %w[elf floresta] => 'wood',
    %w[elf alto_elfo] => 'high',
    %w[elf alto] => 'high',
    %w[elf negro] => 'drow',
    # --- Gnomo / Gnome ---
    %w[gnome forest_gnome] => 'forest',
    %w[gnome rock_gnome] => 'rock',
    %w[gnome gnomo_da_floresta] => 'forest',
    %w[gnome floresta] => 'forest',
    %w[gnome gnomo_das_rochas] => 'rock',
    %w[gnome rocha] => 'rock',
    # --- Halfling ---
    %w[halfling lightfoot_halfling] => 'lightfoot',
    %w[halfling stout_halfling] => 'stout',
    %w[halfling pes_leves] => 'lightfoot',
    ['halfling', 'pés_leves'] => 'lightfoot',  # com acento — não cabe em %w[]
    %w[halfling robusto] => 'stout',
    # --- Humano / Human (Lafiga: subrace `variant`) ---
    %w[human variante] => 'variant',
    # --- Tiefling (Lafiga houserules: 3 sub-raças) ---
    %w[tiefling abissal] => 'abissal',
    %w[tiefling infernal] => 'infernal',
    %w[tiefling ctonico] => 'ctonico',
    ['tiefling', 'ctoníco'] => 'ctonico',      # com acento
    # --- Aarakocra (Lafiga houserules: 3 sub-raças) ---
    %w[aarakocra falconicos] => 'falconicos',
    ['aarakocra', 'falcônicos'] => 'falconicos',  # com acento
    %w[aarakocra nocturnos] => 'nocturnos',
    %w[aarakocra cypselanos] => 'cypselanos',
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

  # Normaliza valores de "alcance" do YAML para Integer.
  #
  # Vários campos do `race_rules.yml` são expressos como Hash `{range: N}`
  # (ex.: `darkvision`, `superior_darkvision`), mas consumidores frequentemente
  # querem só o número. Antes deste helper, `applied[:darkvision].to_i` em
  # Hash retornava 0 (Ruby semantics) e a guarda `> 0` falhava silenciosamente:
  # bug ativo em CPS / RaceEditService / RaceProfileService que mantinha
  # darkvision fora do `race_summary` para 8 raças. Cobertura:
  # spec/services/race_creation_*_bdd_spec.rb.
  #
  # @param value [Hash{range: Integer}, Hash{'range' => Integer}, Integer, String, nil]
  # @return [Integer] 0 se valor ausente/inválido
  def self.normalize_range(value)
    return value.to_i if value.is_a?(Numeric)
    return value.to_i if value.is_a?(String)
    return (value[:range] || value['range']).to_i if value.is_a?(Hash)

    0
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

    # Languages: monta array final (always + escolhidos) E expõe metadado de
    # escolha para o front. Antes, só `languages` era retornado e a UI do
    # Variant Human não tinha como saber que precisava pedir 1 idioma extra
    # (o YAML tem `human.languages.choiceCount: 1` na RAÇA BASE; sub-raça
    # `variant` não declara, herda via deep_merge). O front ficava cego
    # porque consumia só o resultado de `apply`.
    choice_count = merged.dig(:languages, :choiceCount).to_i
    choice_options = Array(merged.dig(:languages, :choiceList))
    requested_picks = Array(selection.dig(:choices, :extraLanguages))
    picks_taken = requested_picks.first(choice_count)

    langs = Array(merged.dig(:languages, :always)).dup
    langs.concat(picks_taken) if choice_count.positive?

    language_choices_required =
      if choice_count.positive?
        {
          count: choice_count,
          options: choice_options.map(&:to_s),
          chosen: picks_taken.map(&:to_s),
          remaining: [choice_count - picks_taken.length, 0].max
        }
      end

    # Extract innate spells from traits
    innate_spells = extract_innate_spells_from_traits(merged[:traits] || [])

    {
      race_id: selection[:race_id],
      subrace_id: selection[:subrace_id],
      ability: merged[:ability],
      speed: merged[:speed],
      # Darkvision: prevalece o MAIOR entre a chave top-level `darkvision`
      # (`{range:N}`) e os traits `darkvision`/`superior_darkvision` (que
      # carregam `range`). Necessário para Aarakocra Nocturnos, cuja visão no
      # escuro é declarada SÓ como trait de sub-raça (sem chave top-level) e
      # antes era perdida (applied[:darkvision]=nil → race_summary sem darkvision).
      darkvision: darkvision_from(merged),
      # R1 — deslocamentos especiais (voo do Aarakocra, escalada do Tabaxi)
      # derivados de `grants.movement` nos trait_defs. Antes, voo/escalada só
      # existiam como TEXTO em traits[].description e nunca chegavam à ficha
      # como campo estruturado (`movement.fly_ft`/`movement.climb_ft`).
      movement: extract_movement_from_traits(merged[:traits] || []),
      languages: langs.uniq,
      language_choices_required: language_choices_required,
      proficiencies: merged[:proficiencies] || {},
      traits: merged[:traits] || [],
      innate_spells: innate_spells,
      requires: merged[:requires] || []
    }
  end

  # Mapeia abreviações de atributo (EN/PT, maiúsc/minúsc) → chave curta PT-BR.
  ABILITY_BONUS_KEY_MAP = {
    'str' => 'str', 'for' => 'str', 'força' => 'str', 'forca' => 'str', 'strength' => 'str',
    'dex' => 'dex', 'des' => 'dex', 'destreza' => 'dex', 'dexterity' => 'dex',
    'con' => 'con', 'constituição' => 'con', 'constituicao' => 'con', 'constitution' => 'con',
    'int' => 'int', 'inteligência' => 'int', 'inteligencia' => 'int', 'intelligence' => 'int',
    'wis' => 'wis', 'sab' => 'wis', 'sabedoria' => 'wis', 'wisdom' => 'wis',
    'cha' => 'cha', 'car' => 'cha', 'carisma' => 'cha', 'charisma' => 'cha',
  }.freeze

  def self.normalize_ability_bonus_key(raw)
    ABILITY_BONUS_KEY_MAP[raw.to_s.strip.downcase]
  end

  # R7 — Converte o bloco `ability` de `apply` num hash plano de bônus RACIAIS
  # `{'con'=>2,'dex'=>1,...}` (chaves curtas PT-BR minúsculas), somando a parte
  # FIXA (regra canônica) com a parte ESCOLHIDA (`chosen_abilities`).
  #
  # É a FONTE AUTORITATIVA server-side de `race_bonuses_applied`, usada por
  # RaceEditService (corrige o bug que zerava ao iterar `{increases:[...]}` como
  # hash plano) e como rede de segurança no CharacterProvisioningService.
  #
  # Type-aware (o deep_merge raça+sub-raça mistura blocos):
  #   - fixed        → soma `increases`
  #   - halfElf      → soma `fixed` (CHA+2) + `choose` (count×amount nos escolhidos)
  #   - variantHuman → SÓ os escolhidos (`chooseAbilities`); ignora `increases`
  #                    herdado do Humano base (senão daria +1 em tudo + escolhas)
  #
  # @param ability [Hash] applied[:ability]
  # @param chosen_abilities [Array<String>] race_choices.chosenAbilities
  # @return [Hash{String=>Integer}] só chaves com bônus != 0
  def self.ability_bonuses(ability, chosen_abilities: [])
    return {} unless ability.is_a?(Hash)

    ab = ability.symbolize_keys
    out = Hash.new(0)
    type = (ab[:type] || ab['type']).to_s

    add_fixed = lambda do |list|
      Array(list).each do |inc|
        next unless inc.is_a?(Hash)

        key = normalize_ability_bonus_key(inc[:ability] || inc['ability'])
        out[key] += (inc[:amount] || inc['amount']).to_i if key
      end
    end

    add_chosen = lambda do |choose|
      return unless choose.is_a?(Hash)

      amount = (choose[:amount] || choose['amount'] || 1).to_i
      count  = (choose[:count] || choose['count']).to_i
      picks  = Array(chosen_abilities).map { |a| normalize_ability_bonus_key(a) }.compact
      picks  = picks.first(count) if count.positive?
      picks.each { |k| out[k] += amount }
    end

    case type
    when 'variantHuman'
      add_chosen.call(ab[:chooseAbilities])
    when 'halfElf'
      add_fixed.call(ab[:fixed])
      add_chosen.call(ab[:choose])
    else
      add_fixed.call(ab[:increases])
    end

    out.reject { |_, v| v.zero? }.transform_keys(&:to_s)
  end

  # Maior alcance de visão no escuro entre a chave top-level e os traits
  # `darkvision`/`superior_darkvision` (que trazem `range` no próprio ref).
  # @return [Integer, nil] alcance em ft quando presente; nil quando não há
  #   (preserva a semântica "blank" do contrato antigo `merged[:darkvision]`,
  #   onde raças sem visão no escuro retornavam nil).
  DARKVISION_TRAIT_KEYS = %w[darkvision superior_darkvision].freeze
  def self.darkvision_from(merged)
    top = normalize_range(merged[:darkvision])
    from_traits = Array(merged[:traits]).map do |ref|
      next 0 unless ref.is_a?(Hash)

      key = (ref[:key] || ref['key']).to_s
      next 0 unless DARKVISION_TRAIT_KEYS.include?(key)

      normalize_range(ref[:range] || ref['range'])
    end.max.to_i
    dv = [top, from_traits].max
    dv.positive? ? dv : nil
  end

  # Deriva deslocamentos especiais (voo/escalada/natação/escavação) a partir
  # de `grants.movement.{fly_ft,climb_ft,swim_ft,burrow_ft}` dos trait_defs.
  # Quando mais de um trait concede o mesmo tipo, prevalece o MAIOR valor.
  # @return [Hash{Symbol=>Integer}] só com chaves presentes (> 0)
  MOVEMENT_GRANT_KEYS = %i[fly_ft climb_ft swim_ft burrow_ft].freeze
  def self.extract_movement_from_traits(traits)
    trait_defs = trait_definitions
    out = {}
    Array(traits).each do |trait_ref|
      trait_key = trait_ref.is_a?(Hash) ? (trait_ref[:key] || trait_ref['key']) : trait_ref
      next unless trait_key

      trait_def = trait_defs[trait_key.to_sym] || trait_defs[trait_key.to_s]
      next unless trait_def

      mv = trait_def.dig(:grants, :movement) || trait_def.dig('grants', 'movement')
      next unless mv.is_a?(Hash)

      MOVEMENT_GRANT_KEYS.each do |f|
        v = (mv[f] || mv[f.to_s]).to_i
        out[f] = [out[f].to_i, v].max if v.positive?
      end
    end
    out
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
