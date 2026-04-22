# frozen_string_literal: true

# Constrói o payload do CharacterProvisioningService a partir de uma ficha
# extraída do XLSX (formato `api/docs/imported_sheets.json`), incluindo as
# decisões obrigatórias por classe/nível em modo strict (default RSpec).
#
# Estratégia:
# - Para `level == 1` o payload é mínimo (Phase 2.0 baseline).
# - Para `level > 1` popula `classPicksByLevel[N]` com:
#     hp + decisões obrigatórias do `ClassRules.required_choices_at_level[N]`
#   defaultando para opções seguras quando a ficha não traz a escolha real.
# - Subclasse vai em `wizard.klass.classSubclassId`; o LevelUpService aplica
#   no nível certo (`Klass#subclass_level`).
#
# NÃO popula magias / cantrips. Casters de magia conhecida (bard, sorcerer,
# warlock, wizard, ranger, cleric, druid) são bloqueados pelo guard se
# faltarem `SheetKnownSpell` registros — isso fica para Phase 2.1.B
# (precisa seed de Spell no test DB).
module ImportedSheetsPayloadBuilder
  module_function

  # Classes que NÃO sofrem bloqueio do guard por falta de SpellKnown
  # (não têm SpellRules.sc_for definido até o level alvo).
  NON_CASTER_CLASSES = %w[barbarian fighter monk rogue cozinheiro].freeze

  # Estilos de combate canônicos do projeto (ver ClassRules::FIGHTING_STYLES).
  DEFAULT_FIGHTING_STYLE = 'Defesa'

  # Defaults para escolhas obrigatórias por classe (apenas chaves usadas
  # pelo guard em strict mode).
  DEFAULTS = {
    fighting_style:   'Defesa',
    favored_enemy:    'Bestas',
    favored_terrain:  'Floresta',
    metamagic_pair:   ['Magia Cuidadosa', 'Magia Gêmea'],
    metamagic_single: ['Magia Estendida'],
    pact_boon:        'Pacto da Lâmina',
    # Slugs canonicos do catalogo eldritch_invocations.yml SEM prereqs (pra
    # nao precisar de Eldritch Blast / pact especifico no test DB).
    invocations_pair: %w[ei-armor-of-shadows ei-beguiling-influence],
    expertise_skills: %w[Atletismo Furtividade]
  }.freeze

  # Fallback quando `sheet['skills']` está vazio (JSON antigo / extracao incompleta).
  DEFAULT_SKILL_PICKS = %w[Atletismo Intimidação Furtividade Percepção].freeze

  # Chaves do `extract_xlsx_sheets.py` → nome PT canónico (`ClassRules::SKILLS_ALL`).
  SKILL_KEY_TO_PT = {
    'acrobatics' => 'Acrobacia',
    'animal_handling' => 'Lidar com Animais',
    'arcana' => 'Arcanismo',
    'athletics' => 'Atletismo',
    'deception' => 'Enganação',
    'history' => 'História',
    'insight' => 'Intuição',
    'intimidation' => 'Intimidação',
    'investigation' => 'Investigação',
    'medicine' => 'Medicina',
    'nature' => 'Natureza',
    'perception' => 'Percepção',
    'performance' => 'Atuação',
    'persuasion' => 'Persuasão',
    'religion' => 'Religião',
    'sleight_of_hand' => 'Prestidigitação',
    'stealth' => 'Furtividade',
    'survival' => 'Sobrevivência'
  }.freeze

  SKILL_LABEL_ALIASES = {
    'historia' => 'História',
    'persuasao' => 'Persuasão',
    'intuicao' => 'Intuição',
    'religiao' => 'Religião',
    'adestrar animais' => 'Lidar com Animais',
    'lidar com animais' => 'Lidar com Animais'
  }.freeze

  # ---------- API pública ---------------------------------------------------

  # Resolve qual é o "level alvo" testável para a ficha. Sobe até o level
  # real da campanha. Casters dependem do `ImportedSheetsSpellSeeder` ter
  # populado ClassLevel/Spellcasting/SpellSource antes do spec rodar.
  def target_level_for(sheet)
    requested = sheet.dig('meta', 'level').to_i
    return 1 if requested < 1

    [requested, 20].min
  end

  def build(sheet, user:, background:, alignment:)
    meta  = sheet['meta']  || {}
    race  = meta['race']   || {}
    klass = meta['klass']  || {}

    target_level = target_level_for(sheet)
    base_attrs   = ability_block(sheet)

    char_name = "#{(meta['name'] || sheet['tab_name']).to_s.strip}-RSpec-#{SecureRandom.hex(2)}"

    l1_skills = class_skill_picks_from_sheet(sheet)
    l1_skills = DEFAULT_SKILL_PICKS if l1_skills.blank?

    {
      character: { name: char_name, background: background.name },
      wizard: {
        meta: { name: meta['name'] || sheet['tab_name'], alignmentKey: alignment.api_index },
        race: {
          ruleId:     race['race_api_index'],
          subRuleId:  race['subrace_api_index'],
          attributes: base_attrs,
          raceChoices: { chosenLanguages: [] }
        },
        klass: {
          klassRuleSlug:    klass['class_api_index'],
          classSubclassId:  klass['subclass_api_index'],
          level:            target_level,
          classSkillPicks:  l1_skills,
          classPicksByLevel: build_per_level(klass['class_api_index'], target_level, base_attrs, sheet, l1_skills)
        },
        background: {
          backgroundName: background.name,
          backgroundKey:  background.api_index
        },
        equipment: {},
        avatar:    { customization: {} }
      }
    }
  end

  # ---------- internals -----------------------------------------------------

  # Perícias de classe: ranqueia `training_hours` no pool PHB da classe (planilha
  # “laranja” ≈ mais horas de treino no extrator Python).
  def class_skill_picks_from_sheet(sheet)
    idx = sheet.dig('meta', 'klass', 'class_api_index').to_s
    return [] if idx.blank?

    rule = ClassRules::CLASS_RULES[idx.to_sym]
    return [] unless rule

    sp = rule[:skill_proficiencies]
    choose = sp&.dig(:choose).to_i
    choose = 2 if choose < 1
    raw_opts = sp&.dig(:options)
    pool = if raw_opts == :any
             ClassRules::SKILLS_ALL
           elsif raw_opts.is_a?(Array) && raw_opts.any?
             raw_opts
           else
             ClassRules::SKILLS_ALL
           end
    allowed = pool.to_set

    ranked = Array(sheet['skills']).filter_map do |r|
      next unless r.is_a?(Hash)

      name = skill_pt_name_from_import_row(r)
      next if name.blank? || !allowed.include?(name)

      hours = (r['training_hours'] || r[:training_hours]).to_f
      [name, hours]
    end.sort_by { |(_, h)| -h }

    picks = []
    ranked.each do |name, _|
      next if picks.include?(name)

      picks << name
      break if picks.size >= choose
    end
    pool.each do |n|
      break if picks.size >= choose

      next if picks.include?(n)

      picks << n
    end
    picks.first(choose)
  rescue StandardError
    []
  end

  def skill_pt_name_from_import_row(row)
    k = row['key'].to_s
    return SKILL_KEY_TO_PT[k] if SKILL_KEY_TO_PT[k]

    canonical_skill_pt(row['label'] || row['raw_label_in_sheet'])
  end

  def canonical_skill_pt(raw)
    s = raw.to_s.strip
    return nil if s.empty?

    key = s.unicode_normalize(:nfd).gsub(/\p{M}/, '').downcase.gsub(/\s+/, ' ')
    return SKILL_LABEL_ALIASES[key] if SKILL_LABEL_ALIASES[key]

    ClassRules::SKILLS_ALL.find do |pt|
      pt.unicode_normalize(:nfd).gsub(/\p{M}/, '').casecmp?(key)
    end
  end

  def ability_block(sheet)
    abilities = sheet['abilities'] || {}
    {
      'str' => score(abilities, 'strength'),
      'dex' => score(abilities, 'dexterity'),
      'con' => score(abilities, 'constitution'),
      'int' => score(abilities, 'intelligence'),
      'wis' => score(abilities, 'wisdom'),
      'cha' => score(abilities, 'charisma')
    }
  end

  def score(abilities, key)
    raw = abilities.dig(key, 'score') || abilities[key]
    val = raw.is_a?(Numeric) ? raw.to_i : raw.to_i
    val.between?(1, 30) ? val : 10
  end

  # Constrói `classPicksByLevel` cobrindo do nível 1 ao target_level.
  # Cada linha tem: hp + decisões obrigatórias daquele nível (do ClassRules).
  def build_per_level(class_idx, target_level, base_attrs, sheet, l1_skills)
    klass_record = Klass.find_by(api_index: class_idx)
    hd           = klass_record&.hit_die.to_i.nonzero? || 8
    con_mod      = (base_attrs['con'] - 10) / 2

    rule = (ClassRules::CLASS_RULES[class_idx.to_sym] rescue nil) || {}
    per_required = rule[:required_choices_at_level] || {}

    # PHB "fixed average": ceil(hd/2) + 1 a partir do level 2
    # (Player's Handbook p.15). O LevelUpService trata `dieResult` como o
    # valor "rolado" do dado e soma con_mod por cima — então passamos
    # ceil(hd/2)+1 para que `step_gain = (ceil(hd/2)+1) + con_mod`.
    fixed_avg_per_level = (hd / 2) + 1

    # Phase 2.2.A — bonus HP por feat/race (Robusto/Toughness, Hill Dwarf,
    # Draconic Resilience). Embutido no `hp.total` de cada nível pra zerar
    # diff vs XLSX nas fichas que têm essas vantagens.
    bonus_per_level = hp_bonus_per_level(sheet, class_idx)

    rows = {}
    (1..target_level).each do |lv|
      base_die  = lv == 1 ? hd : fixed_avg_per_level
      # LevelUpService usa `dieResult` direto (ignora `total`). Para refletir
      # bonus de feat/race no HP final, somamos no proprio dieResult.
      die_result = base_die + bonus_per_level
      hp_total   = [die_result + con_mod, 1].max
      row = { 'hp' => { 'dieResult' => die_result, 'total' => hp_total, 'method' => 'fixed' } }

      # Skills L1 (canônico) — mesmas picks que `classSkillPicks` (inferidas do XLSX).
      if lv == 1
        row['skills'] = l1_skills
      end

      # Decisões obrigatórias declaradas para este nível
      level_choices = per_required[lv] || per_required[lv.to_s] || {}
      level_choices.each do |key, conf|
        row[key.to_s] = default_for(key, conf, sheet, lv)
      end

      rows[lv.to_s] = row
    end
    rows
  end

  def default_for(key, conf, sheet, _level)
    case key.to_s
    when 'fighting_style'
      ImportedSheetsPayloadBuilder.fighting_style_for(sheet) || DEFAULTS[:fighting_style]
    when 'favored_enemy'
      DEFAULTS[:favored_enemy]
    when 'favored_terrain'
      DEFAULTS[:favored_terrain]
    when 'expertise_skills'
      need = conf[:choose].to_i.nonzero? || 2
      DEFAULTS[:expertise_skills].first(need)
    when 'metamagic'
      need = conf[:choose].to_i.nonzero? || 1
      need >= 2 ? DEFAULTS[:metamagic_pair] : DEFAULTS[:metamagic_single]
    when 'invocations'
      DEFAULTS[:invocations_pair]
    when 'pact_boon'
      DEFAULTS[:pact_boon]
    else
      # Fallback safe: pega primeira opção do catálogo se for resolvível
      Array(conf[:options]).first
    end
  end

  # Retorna bonus de HP por nível somando contribuições de feats/race que a
  # ficha XLSX declara explicitamente. Usado pelo Phase 2.2.A.
  #   • Robusto / Toughness                   → +2/lvl
  #   • Hill Dwarf (anão da colina)           → +1/lvl
  #   • Draconic Resilience (sorcerer/draconic) → +1/lvl
  def hp_bonus_per_level(sheet, class_idx)
    bonus = 0
    feats = Array(sheet['feats']).map { |f| f.to_s.downcase.strip }
    bonus += 2 if feats.any? { |f| f.include?('robusto') || f.include?('toughness') }

    race    = sheet.dig('meta', 'race', 'race_api_index').to_s.downcase
    subrace = sheet.dig('meta', 'race', 'subrace_api_index').to_s.downcase
    bonus += 1 if race == 'dwarf' && subrace == 'hill'

    sub_klass = sheet.dig('meta', 'klass', 'subclass_api_index').to_s.downcase
    bonus += 1 if class_idx == 'sorcerer' && sub_klass.include?('draconic')

    bonus
  end

  # Phase 2.5 — converte feats extraídos da XLSX (ex.: ["Mobilidade",
  # "Observador"]) para o formato esperado por FeatProducer
  # (`metadata['feats']`): array de hashes com `feat_id` canônico.
  # Usa FeatRules.aliases para fuzzy match ("Mobilidade" → "mobilidade").
  # Feats não-mapeáveis são ignorados (não causam falha no spec).
  def feats_metadata_for(sheet)
    raw = Array(sheet['feats']).map { |s| s.to_s.strip }.reject(&:empty?)
    return [] if raw.empty?

    raw.filter_map do |feat_label|
      canonical = canonical_feat_id(feat_label)
      next nil unless canonical
      { 'feat_id' => canonical, 'choices' => {}, 'source' => 'imported_xlsx' }
    end
  end

  def canonical_feat_id(label)
    norm = label.to_s.downcase.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').strip
    return nil if norm.empty?

    FeatRules::RULES.each do |id, conf|
      candidates = [id.to_s.downcase, conf[:name].to_s.downcase.unicode_normalize(:nfd).gsub(/\p{Mn}/, '')]
      candidates += Array(conf[:aliases]).map { |a| a.to_s.downcase.unicode_normalize(:nfd).gsub(/\p{Mn}/, '') }
      return id.to_s if candidates.include?(norm)
    end
    nil
  end

  def fighting_style_for(sheet)
    raw = sheet['fighting_style']
    return nil if raw.blank?

    if defined?(FightingStyleRules) && FightingStyleRules.respond_to?(:canonicalize)
      FightingStyleRules.canonicalize(raw)
    else
      raw
    end
  end
end
