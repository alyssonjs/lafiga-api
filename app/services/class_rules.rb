class ClassRules
  INSTRUMENTS = [
    'Gaita de Foles', 'Tambor', 'Saltério', 'Flauta', 'Alaúde', 
    'Lira', 'Trompa', 'Flauta de Pã', 'Charamela', 'Violino'
  ].freeze
  FIGHTING_STYLES = [
    'Defesa', 'Arquearia', 'Duelos', 'Combate com Duas Armas',
    'Proteção', 'Grande Arma'
  ].freeze

  # Variacoes usadas em fichas legadas / planilhas de jogadores que apontam
  # para o mesmo Fighting Style canonico. Use FightingStyleRules.canonicalize(name)
  # para resolver. Mantemos so os apelidos comuns observados em campo.
  FIGHTING_STYLE_ALIASES = {
    'Armas Grandes'      => 'Grande Arma',
    'Armas Grande'       => 'Grande Arma',
    'Combate com A. G.'  => 'Grande Arma',
    'Combate com A.G.'   => 'Grande Arma',
    'Great Weapon'       => 'Grande Arma',
    'Two-Weapon Fighting' => 'Combate com Duas Armas',
    'Combate com Dual'   => 'Combate com Duas Armas',
    'Dual Wielding'      => 'Combate com Duas Armas',
    'Defense'            => 'Defesa',
    'Archery'            => 'Arquearia',
    'Dueling'            => 'Duelos',
    'Protection'         => 'Proteção'
  }.freeze

  ARTISAN_TOOLS = [
    'Ferramentas de Alquimista','Ferramentas de Ferreiro','Ferramentas de Carpinteiro','Ferramentas de Cartógrafo',
    'Ferramentas de Sapateiro','Ferramentas de Artesão (Cozinheiro)','Utensílios de Cozinheiro','Ferramentas de Calígrafo','Ferramentas de Vidraceiro',
    'Ferramentas de Joalheiro','Ferramentas de Coureiro','Ferramentas de Entalhador','Ferramentas de Funileiro','Ferramentas de Pedreiro','Ferramentas de Pintor',
    'Ferramentas de Oleiro','Ferramentas de Ferreiro de Armaduras','Ferramentas de Tecelão','Ferramentas de Marceneiro',
    'Ferramentas de Cervejeiro','Kit de Disfarce','Kit de Falsificação','Kit de Herbalismo',
    'Ferramentas de Ladrão'
  ].freeze

  SKILLS_ALL = [
    'Acrobacia','Arcanismo','Atletismo','Atuação','Enganação','Furtividade','História','Intimidação',
    'Intuição','Investigação','Lidar com Animais','Medicina','Natureza','Percepção',
    'Persuasão','Prestidigitação','Religião','Sobrevivência'
  ].freeze

  # === (Opcional) dicionários-base de grupos, caso queira normalizar no engine ===
  ARMOR_GROUPS  = %w[light medium heavy shield].freeze
  WEAPON_GROUPS = %w[simple martial].freeze

  def self.rules
    raw_rules = Rails.cache.fetch('class_rules_v1', expires_in: 12.hours) { CLASS_RULES }
    
    # Traduzir saving_throws de todas as classes
    translated_rules = {}
    raw_rules.each do |key, rule|
      translated_rule = rule.deep_dup
      if translated_rule[:saving_throws].present?
        translated_rule[:saving_throws] = SavingThrowsCatalog.translate_array(translated_rule[:saving_throws])
      end
      translated_rules[key] = translated_rule
    end
    
    translated_rules
  end

  # SRD (`CLASS_RULES` + tradução) fundido com `klasses.rules` (JSONB). Sobrescreve
  # a mesma chave `api_index` e acrescenta classes só no DB (homebrew) — alinhado a
  # `ClassRules.find` (prioridade DB).
  def self.rules_with_klass_table
    base = rules.deep_dup
    merge_klass_table_rules!(base)
    base
  end

  def self.merge_klass_table_rules!(base)
    Klass.find_each do |k|
      next if k.read_attribute(:rules).blank?

      r = KlassClassRulesProvider.call(k.api_index)
      next unless r

      base[k.api_index.to_sym] = r
    end
  end

  def self.dictionaries
    {
      instruments: INSTRUMENTS,
      artisan_tools: ARTISAN_TOOLS,
      fighting_styles: FIGHTING_STYLES,
      skills_all: SKILLS_ALL,
      invocations_core: [
        'Agonizing Blast',
        'Armor of Shadows',
        'Ascendant Step',
        'Beast Speech',
        'Beguiling Influence',
        'Bewitching Whispers',
        'Book of Ancient Secrets',
        'Chains of Carceri',
        'Devil\'s Sight',
        'Dreadful Word',
        'Eldritch Sight',
        'Eldritch Spear',
        'Eyes of the Rune Keeper',
        'Fiendish Vigor',
        'Gaze of Two Minds',
        'Lifedrinker',
        'Mask of Many Faces',
        'Master of Myriad Forms',
        'Minions of Chaos',
        'Mire the Mind',
        'Misty Visions',
        'One with Shadows',
        'Otherworldly Leap',
        'Repelling Blast',
        'Sculptor of Flesh',
        'Sign of Ill Omen',
        'Thief of Five Fates',
        'Thirsting Blade',
        'Visions of Distant Realms',
        'Voice of the Chain Master',
        'Whispers of the Grave',
        'Witch Sight'
      ],
      ranger_favored_enemy_types: [
        'Aberrações','Bestas','Celestiais','Constructos','Dragões','Elementais','Fadas',
        'Infernais','Gigantes','Monstruosidades','Lodos','Plantas','Mortos-vivos',
        'Humanoides (2 raças)'
      ],
      ranger_favored_terrain_types: [
        'Ártico','Costeiro','Deserto','Floresta','Pradaria','Montanha','Pântano','Subterrâneo'
      ],
      ranger_humanoid_races: [
        'Humano','Elfo','Anão','Halfling','Gnomo','Orc','Goblinoide','Gnoll','Kobold','Hobgoblin','Bugbear','Tritão','Draconato'
      ],
      # Kit 1.PoC: catálogo canônico de metamágicas (Array<Hash> com slug+name_pt+name_en+aliases)
      metamagic: ClassChoicesCatalog.load(:metamagic),
      # Kit 1.invocations: catálogo canônico de invocações místicas
      # (Array<Hash> com slug+name_pt+name_en+aliases+prereqs estruturados).
      # invocations_core (acima) é mantido apenas para retrocompat de chars
      # legados; novas validações usam :eldritch_invocations.
      eldritch_invocations: ClassChoicesCatalog.load(:eldritch_invocations),
      # Kit 1.maneuvers: catálogo canônico das 16 manobras do Battle Master
      # (Fighter subclass). Sem prereqs duros — todas elegíveis a partir do
      # nv 3 quando a subclasse Battle Master é escolhida. A validação
      # de count by level (3/7/10/15) é aplicada no LevelUpGuardService
      # condicionada à subclasse — ver bloco fighter/battlemaster lá.
      maneuvers: ClassChoicesCatalog.load(:maneuvers),
      # Kit 1.disciplines: catálogo canônico das 17 disciplinas do Caminho dos
      # Quatro Elementos (Monk subclass). Prereqs.level codifica os tiers
      # PHB (3/6/11/17). Validação subclass-aware no LevelUpGuardService —
      # ver bloco monk/four_elements lá.
      elemental_disciplines: ClassChoicesCatalog.load(:elemental_disciplines),
      # Kit 1.snacks: catálogo canônico de 42 petiscos do Cozinheiro (homebrew
      # Lafiga). Prereqs.level codifica gates de nível (7/11/15/18) e
      # prereqs.subclass codifica gating por subclasse (Sous Chef, Sargento,
      # Mestre-Cuca, Mestre Cervejeiro). Validação no LevelUpGuardService
      # com count vindo de feature_rules.cook.snacks.known_by_level.
      snacks: ClassChoicesCatalog.load(:snacks)
    }
  end

  # Regras por `api_index`: DB (`klasses.rules`) tem prioridade sobre o hash em código
  # (`CLASS_RULES`). Isto permite migrar gradualmente sem remover o legado de uma vez.
  def self.find(id)
    from_db = KlassClassRulesProvider.call(id)
    return from_db if from_db

    find_from_rules_constant(id)
  end

  # Apenas o hash `ClassRules.rules` + tradução de saving_throws (comportamento pré-DB).
  def self.find_from_rules_constant(id)
    rule = rules[id.to_s]
    return nil unless rule

    rule = rule.deep_dup
    if rule[:saving_throws].present?
      rule[:saving_throws] = SavingThrowsCatalog.translate_array(rule[:saving_throws])
    end

    rule
  end

  # === Subclasses: mantido como estava, com os enriquecimentos ===
  def self.available_subclasses(klass_id)
    rule = find(klass_id)
    return [] unless rule

    static_subclasses = rule.dig(:subclass, :options) || {}
    klass_record = Klass.find_by(api_index: klass_id)
    custom_subclasses = {}

    if klass_record
      grant_maps = {}
      klass_record.sub_klasses.each do |sub_klass|
        next if sub_klass.api_index.blank?
        grants_by_level = {}
        begin
          parsed = JSON.parse(sub_klass.levels_json || '[]')
          parsed.each do |row|
            lvl = row['level'].to_i
            g = row['grants'] || {}
            ch = row['choices'] || {}
            add_choices = {}
            if g['languages'].is_a?(Hash) && g['languages']['choose'].to_i > 0
              add_choices['languages'] = { choose: g['languages']['choose'], options: g['languages']['options'] || [] }
            end
            prof = g['proficiencies'] || {}
            %w[skills tools instruments].each do |k|
              v = prof[k]
              if v.is_a?(Hash) && v['choose'].to_i > 0
                add_choices[k] = { choose: v['choose'], options: v['options'] || [] }
              end
            end
            fs = g['fighting_style']
            if fs.is_a?(Hash) && fs['choose'].to_i > 0
              add_choices['fighting_style'] = { choose: fs['choose'], options: fs['options'] || [] }
            end
            if ch.is_a?(Hash)
              ch.each do |key, val|
                next unless val.is_a?(Hash)
                next unless val['choose'].to_i > 0
                options = val['options'] || []
                add_choices[key] = { choose: val['choose'], options: options }
              end
            end
            grants_by_level[lvl] = add_choices if add_choices.any?
          end
        rescue
          grants_by_level = {}
        end

        learn_any_map = {}
        begin
          parsed = JSON.parse(sub_klass.levels_json || '[]')
          parsed.each do |row|
            lvl = row['level'].to_i
            next if lvl <= 0
            val = row.dig('grants','spells','learn_any_class')
            if val && val.to_i > 0
              learn_any_map[lvl.to_s] = val.to_i
            end
          end
        rescue
          learn_any_map = {}
        end

        custom_subclasses[sub_klass.api_index] = {
          id: sub_klass.api_index,
          name: sub_klass.name,
          custom: true,
          description: sub_klass.description,
          additional_choices_by_level: grants_by_level,
          learn_any_class_by_level: learn_any_map
        }
      end
    end

    all_subclasses = static_subclasses.merge(custom_subclasses)

    all_subclasses.map do |key, subclass|
      always_map = {}
      expanded_map = {}
      choices_yaml_by_level = {}
      always_by_terrain = {}

      # NOVO: chave base para YAML mesmo sem DB
      api_key = klass_record&.api_index || rule[:id]

      begin
        if klass_record
          sub_rec = klass_record.sub_klasses.find { |sk| sk.api_index.to_s == key.to_s }
          if sub_rec
            rel = SpellSource.where(source_type: 'SubKlass', source_id: sub_rec.id, always_prepared: true)
            rel.group_by { |ss| (ss.min_class_level || 1).to_i }
               .sort_by { |lvl, _| lvl }
               .each do |lvl, list|
                 ids = list.map(&:spell_id).uniq
                 names = Spell.where(id: ids).pluck(:name)
                 always_map[lvl.to_s] = names
               end
            rel2 = SpellSource.where(source_type: 'SubKlass', source_id: sub_rec.id)
                              .where("coalesce(notes,'') = ?", 'expanded')
            rel2.group_by { |ss| (ss.min_class_level || 1).to_i }
                .sort_by { |lvl, _| lvl }
                .each do |lvl, list|
                  ids = list.map(&:spell_id).uniq
                  names = Spell.where(id: ids).pluck(:name)
                  expanded_map[lvl.to_s] = names
                end
          end
        end
      rescue => _e
        always_map = {}
        expanded_map = {}
      end

      # Fallbacks de YAML (subclass_overrides.yml)
      if always_map.blank? || choices_yaml_by_level.blank? || always_by_terrain.blank?
        begin
          path = Rails.root.join('config','subclass_overrides.yml')
          if File.exist?(path)
            yml = YAML.load_file(path) || {}
            ent = yml.dig(api_key, key)
            if ent && ent['levels']
              ent['levels'].each do |row|
                Array(row['features']).each do |feat|
                  grants = (feat['grants'] || {})
                  spells = (grants['spells'] || {})

                  ap = (spells['always_prepared'] || {})
                  ap.each do |lvl, list|
                    names = Array(list).map do |nm|
                      sl = nm.is_a?(String) ? nm : nm.to_s
                      sp = Spell.find_by(api_index: sl)
                      sp ? sp.name : sl
                    end
                    lvl_key = lvl.to_s
                    always_map[lvl_key] = ((always_map[lvl_key] || []) | names)
                  end

                  ap_terr = (spells['always_prepared_by_terrain'] || {})
                  ap_terr.each do |terrain_key, lvl_map|
                    next unless lvl_map.is_a?(Hash)
                    always_by_terrain[terrain_key.to_s] ||= {}
                    lvl_map.each do |lvl, list|
                      names = Array(list).map { |nm| nm.to_s }
                      lk = lvl.to_s
                      always_by_terrain[terrain_key.to_s][lk] = ((always_by_terrain[terrain_key.to_s][lk] || []) | names)
                    end
                  end

                  add_can = spells['add_cantrips_from_class'] || {}
                  add_cnt = add_can['count'] || add_can[:count]
                  if add_cnt.to_i > 0
                    lvl_key = row['level'].to_s
                    choices_yaml_by_level[lvl_key] ||= {}
                    choices_yaml_by_level[lvl_key]['cantrips'] ||= { 'choose' => 0 }
                    choices_yaml_by_level[lvl_key]['cantrips']['choose'] = [choices_yaml_by_level[lvl_key]['cantrips']['choose'].to_i, add_cnt.to_i].max
                    src_klass = add_can['class'] || add_can[:class] || add_can['from_class'] || add_can[:from_class]
                    choices_yaml_by_level[lvl_key]['cantrips']['from_class'] = src_klass if src_klass.present?
                  end

                  ch = (feat['choices'] || {})
                  ch.each do |ck, conf|
                    next unless conf.is_a?(Hash)
                    choose = (conf['choose'] || conf[:choose]).to_i
                    next unless choose > 0
                    opts = conf['options'] || conf[:options] || []
                    lvl_key = row['level'].to_s
                    choices_yaml_by_level[lvl_key] ||= {}
                    choices_yaml_by_level[lvl_key][ck.to_s] ||= { 'choose' => 0, 'options' => [] }
                    choices_yaml_by_level[lvl_key][ck.to_s]['choose'] = [choices_yaml_by_level[lvl_key][ck.to_s]['choose'].to_i, choose].max
                    choices_yaml_by_level[lvl_key][ck.to_s]['options'] |= Array(opts)
                  end
                end
              end
            end
          end
        rescue => _e
        end
      end

      # Fallbacks de YAML (subclass.yml)
      if always_map.blank? || expanded_map.blank? || choices_yaml_by_level.blank? || always_by_terrain.blank?
        begin
          path3 = Rails.root.join('config','subclass.yml')
          if File.exist?(path3)
            y3 = YAML.load_file(path3) || {}
            cls_block = y3[api_key]
            if cls_block.is_a?(Hash)
              target_key, target_val = cls_block.find do |k, v|
                vn = (v.is_a?(Hash) ? v['name'] : nil)
                (k.to_s == key.to_s) || (vn && vn.to_s.downcase == (subclass[:name] || '').to_s.downcase)
              end
              if target_val.is_a?(Hash)
                levels = Array(target_val['levels'])
                levels.each do |row|
                  feats = Array(row['features'])
                  feats = [ { 'grants' => row['grants'], 'choices' => row['choices'] } ] if feats.empty? && (row['grants'] || row['choices'])
                  feats.each do |feat|
                    grants = (feat['grants'] || {})
                    spells = (grants['spells'] || {})

                    ap1 = (spells['always_prepared'] || {})
                    ap1.each do |lvl, list|
                      names = Array(list).map { |nm| nm.to_s }
                      lvl_key = lvl.to_s
                      always_map[lvl_key] = ((always_map[lvl_key] || []) | names)
                    end

                    ap_terr = (spells['always_prepared_by_terrain'] || {})
                    ap_terr.each do |terrain_key, lvl_map|
                      next unless lvl_map.is_a?(Hash)
                      always_by_terrain[terrain_key.to_s] ||= {}
                      lvl_map.each do |lvl, list|
                        names = Array(list).map { |nm| nm.to_s }
                        lk = lvl.to_s
                        always_by_terrain[terrain_key.to_s][lk] = ((always_by_terrain[terrain_key.to_s][lk] || []) | names)
                      end
                    end

                    add_can = spells['add_cantrips_from_class'] || {}
                    add_cnt = add_can['count'] || add_can[:count]
                    if add_cnt.to_i > 0
                      lvl_key = row['level'].to_s
                      choices_yaml_by_level[lvl_key] ||= {}
                      choices_yaml_by_level[lvl_key]['cantrips'] ||= { 'choose' => 0 }
                      choices_yaml_by_level[lvl_key]['cantrips']['choose'] = [choices_yaml_by_level[lvl_key]['cantrips']['choose'].to_i, add_cnt.to_i].max
                      src_klass = add_can['class'] || add_can[:class] || add_can['from_class'] || add_can[:from_class]
                      choices_yaml_by_level[lvl_key]['cantrips']['from_class'] = src_klass if src_klass.present?
                    end

                    ch = (feat['choices'] || {})
                    ch.each do |ck, conf|
                      next unless conf.is_a?(Hash)
                      choose = (conf['choose'] || conf[:choose]).to_i
                      next unless choose > 0
                      opts = conf['options'] || conf[:options] || []
                      lvl_key = row['level'].to_s
                      choices_yaml_by_level[lvl_key] ||= {}
                      choices_yaml_by_level[lvl_key][ck.to_s] ||= { 'choose' => 0, 'options' => [] }
                      choices_yaml_by_level[lvl_key][ck.to_s]['choose'] = [choices_yaml_by_level[lvl_key][ck.to_s]['choose'].to_i, choose].max
                      choices_yaml_by_level[lvl_key][ck.to_s]['options'] |= Array(opts)
                    end
                  end
                end
                if target_val['expanded_spells'].is_a?(Hash)
                  target_val['expanded_spells'].each do |lvl, arr|
                    names = Array(arr).map { |nm| nm.to_s }
                    expanded_map[lvl.to_s] = ((expanded_map[lvl.to_s] || []) | names)
                  end
                end
              end
            end
          end
        rescue => _e
        end
      end

      spellcasting_data = nil
      school_restrictions = nil
      begin
        if klass_record
          sub_rec = klass_record.sub_klasses.find { |sk| sk.api_index.to_s == key.to_s }
          if sub_rec
            sc_entry = SubclassSpellcasting.lookup(
              klass_api: klass_record.api_index,
              subclass_api: sub_rec.api_index,
              level: 3
            )
            if sc_entry
              spellcasting_data = {
                ability: sc_entry.ability,
                list_source_klass: sc_entry.list_source_klass,
                cantrips_known: sc_entry.cantrips_known,
                spells_known: sc_entry.spells_known,
                slots: sc_entry.slots
              }
              yml_data = SubclassSpellcasting.yml.dig(klass_record.api_index, sub_rec.api_index)
              if yml_data && yml_data['school_restrictions']
                school_restrictions = yml_data['school_restrictions']
              end
            end
          end
        end
      rescue => _e
      end

      {
        id: key,
        name: subclass[:name],
        custom: subclass[:custom] || false,
        description: subclass[:description],
        additional_choices_by_level: (subclass[:additional_choices_by_level] || {}).merge(choices_yaml_by_level),
        learn_any_class_by_level: (subclass[:learn_any_class_by_level] || {}),
        always_prepared: always_map,
        always_prepared_by_terrain: always_by_terrain,
        expanded_spells: expanded_map,
        spellcasting: spellcasting_data,
        school_restrictions: school_restrictions
      }
    end.sort_by { |s| s[:name] }
  end

  # === APPLY ORIGINAL (mantido para compatibilidade) ===
  def self.apply(selection)
    rule = find(selection[:klass_id])
    raise ArgumentError, 'class not found' unless rule
    level = selection[:level].to_i.nonzero? || 1
    picks = selection[:picks] || {}

    armor = Array(rule[:armor_proficiencies])
    weapons = Array(rule[:weapon_proficiencies])
    tools = Array(rule[:tool_proficiencies])

    if rule.dig(:tool_proficiencies, :instruments, :choose)
      chosen = Array(selection[:instruments_selected]).map { |x| (x.is_a?(Hash) ? x[:name] : x).to_s }
      tools << { instruments: chosen.first(rule[:tool_proficiencies][:instruments][:choose].to_i) }
    end

    class_skills = if rule.dig(:skill_proficiencies, :options) == :any
                     SKILLS_ALL
                   else
                     Array(rule.dig(:skill_proficiencies, :options))
                   end
    skills_chosen = Array(selection[:skills_selected]).map { |x| (x.is_a?(Hash) ? x[:name] : x).to_s }
    skills = skills_chosen.first(rule.dig(:skill_proficiencies, :choose).to_i)

    required = (rule[:required_choices_at_level] || {}).select { |lvl, _| lvl.to_i <= level }
    required_summary = {}
    required.each do |_key_level, h|
      h.each do |key, conf|
        chosen = picks[key] || picks[key.to_s]
        if conf[:choose].to_i > 1
          chosen = Array(chosen).first(conf[:choose].to_i)
        end
        required_summary[key] = chosen
      end
    end

    subclass = nil
    if rule.dig(:subclass, :choose_level).to_i > 0 && level >= rule.dig(:subclass, :choose_level).to_i
      sc_id = picks[:subclass_id] || picks['subclass_id']
      subclass = rule.dig(:subclass, :options, sc_id.to_sym) if sc_id
      unless subclass
        klass_record = Klass.find_by(api_index: rule[:id])
        if klass_record
          sub_klass_record = klass_record.sub_klasses.find_by(api_index: sc_id)
          if sub_klass_record
            subclass = { id: sub_klass_record.api_index, name: sub_klass_record.name, custom: true }
          end
        end
      end
    end

    {
      klass_id: rule[:id],
      name: rule[:name],
      hit_die: rule[:hit_die],
      primary_abilities: rule[:primary_abilities],
      saving_throws: SavingThrowsCatalog.translate_array(rule[:saving_throws]),
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

  # === Interpretador genérico para feature_rules ===
  def self.derive_feature_rules(rule:, level:, picks: {}, ability_scores: {}, equipment: {})
    fr = (rule[:feature_rules] || {}).with_indifferent_access
    out = {
      ac: nil,
      speed_bonus_m: 0,
      resources: {},
      rest_bonuses: {},
      crit: nil,
      floors: {},
      ability_caps: {},
      ability_increases_pending: 0,
      choices: {},
      auras: {},
      proficiency_overrides: {},
      combat_toggles: {},
      spellcasting_meta: {},
      proficiencies: {
        armor: Array(rule[:armor_proficiencies]),
        weapons: Array(rule[:weapon_proficiencies]),
        tools: Array(rule[:tool_proficiencies])
      }
    }

    armor_category = (equipment[:armor_category] || equipment['armor_category']).to_s
    wearing_armor  = !!(equipment[:armor_equipped] || equipment['armor_equipped'])

    cha = (ability_scores[:CHA] || ability_scores['CHA']).to_i
    mnk_lvl = (picks[:monk_level] || level).to_i

    # --- Unarmored Defense (bárbaro/monge) ---
    if ud = fr[:unarmored_defense]
      if level >= (ud[:level] || 1).to_i && !wearing_armor
        out[:ac] = { formula: (ud[:formula] || "10 + DEX + CON"), allows_shield: !!ud[:allows_shield] }
      end
    end

    # --- Movimento Rápido (bárbaro) / Movimento sem Armadura (monge) ---
    if fm = fr[:fast_movement]
      if level >= (fm[:level] || 5).to_i
        blocked = fm.dig(:unless, :armor_category).to_s == 'heavy' && armor_category == 'heavy'
        out[:speed_bonus_m] += (blocked ? 0 : fm[:add].to_i)
      end
    end
    if uam = fr[:unarmored_movement]
      bonus_ft = 0
      (uam[:bonus_ft_by_level] || {}).each { |lvl,ft| bonus_ft = [bonus_ft, ft.to_i].max if level >= lvl.to_i }
      out[:speed_bonus_m] += (bonus_ft * 0.3048).round
    end

    # --- Crítico Brutal (bárbaro) ---
    if bc = fr[:brutal_critical]
      extra = 0
      (bc[:scaling_by_level] || {}).each { |lvl, n| extra = [extra, n.to_i].max if level >= lvl.to_i }
      out[:crit] = { brutal_critical_extra_dice: extra, die_source: :weapon, applies_when: { melee_using: 'STR' } } if extra > 0
    end

    # --- Força Indomável (bárbaro) ---
    if im = fr[:indomitable_might]
      out[:floors][:strength_checks] = :ability_score if level >= (im[:level] || 18).to_i
    end

    # --- Campeão Primitivo (bárbaro) ---
    if pc = fr[:primal_champion]
      if level >= (pc[:level] || 20).to_i
        (pc[:caps] || {}).each { |k,v| out[:ability_caps][k.to_s] = v.to_i }
        out[:choices][:primal_champion_apply] = { "20" => { increases: (pc[:fixed] || { "STR"=>4, "CON"=>4 }) } }
      end
    end

    # --- ASIs (todas as classes) ---
    if asi = fr[:ability_score_improvement]
      out[:ability_increases_pending] = Array(asi[:levels]).count { |lv| level >= lv.to_i }
    end

    # --- Bardic Inspiration ---
    if bi = fr[:bardic_inspiration]
      die = case level
            when 15.. then 'd12'
            when 10.. then 'd10'
            when 5..  then 'd8'
            else 'd6'
            end
      uses = [1, cha].max
      recharge = (level >= 5 ? 'SR' : 'LR')
      out[:resources][:bardic_inspiration] = { uses:, recharge:, die: die }
    end

    # --- Jack of All Trades ---
    if joat = fr[:jack_of_all_trades]
      if level >= (joat[:level] || 2).to_i
        out[:proficiency_overrides][:half_proficiency_on_non_proficient_checks] = true
        out[:proficiency_overrides][:applies_to_initiative] = true
      end
    end

    # --- Canção de Descanso ---
    if sor = fr[:song_of_rest]
      die = case level
            when 17.. then 'd12'
            when 13.. then 'd10'
            when 9..  then 'd8'
            else 'd6'
            end
      out[:rest_bonuses][:song_of_rest_die] = die
    end

    # --- Expertise (bardo/ladino) ---
    if exp = fr[:expertise]
      map = {}
      Array(exp[:gains]).each { |g| map[g[:level].to_s] = g[:count].to_i if level >= g[:level].to_i }
      out[:choices][:expertise] = map if map.any?
    end

    # --- Magical Secrets (bardo) ---
    if ms = fr[:magical_secrets]
      map = {}
      Array(ms[:gains]).each { |g| map[g[:level].to_s] = g[:learn].to_i if level >= g[:level].to_i }
      out[:choices][:magical_secrets] = map if map.any?
    end

    # --- Channel Divinity / Destroy Undead / Divine Intervention (clérigo) ---
    if cd = fr[:channel_divinity]
      uses = 0
      (cd[:uses_by_level] || {}).each { |lvl, u| uses = [uses, u.to_i].max if level >= lvl.to_i }
      out[:resources][:channel_divinity] = { uses:, recharge: (cd[:recharge] || 'SR') } if uses > 0
    end
    if du = fr[:destroy_undead]
      cr = 0
      (du[:cr_threshold_by_level] || {}).each { |lvl, threshold| cr = [cr, threshold.to_f].max if level >= lvl.to_i }
      out[:choices][:destroy_undead_cr_threshold] = cr if cr > 0
    end
    if di = fr[:divine_intervention]
      out[:choices][:divine_intervention] = { available: level >= di[:available_at].to_i, auto_success: level >= di[:auto_success_at].to_i }
    end

    # --- Wild Shape (druida) ---
    if ws = fr[:wild_shape]
      uses = ws[:uses].to_i
      cr = 0.0
      swim = level >= ws[:swim_at_level].to_i
      fly  = level >= ws[:fly_at_level].to_i
      (ws[:cr_limit_by_level] || {}).each { |lvl, v| cr = [cr, v.to_f].max if level >= lvl.to_i }
      out[:resources][:wild_shape] = { uses:, recharge: (ws[:recharge] || 'SR'), cr_limit: cr, swim:, fly: }
    end

    # --- Fighting Style (guerreiro/paladino/patrulheiro) ---
    if fs = fr[:fighting_style]
      out[:combat_toggles][:fighting_style_options] = fs[:options]
    end

    # --- Fighter resources ---
    if sw = fr[:second_wind]
      out[:resources][:second_wind] = { uses: (sw[:uses] || 1), recharge: (sw[:recharge] || 'SR'), heal_formula: (sw[:heal_formula] || '1d10 + level') }
    end
    if as = fr[:action_surge]
      uses = 0
      (as[:uses_by_level] || {}).each { |lvl,u| uses = [uses, u.to_i].max if level >= lvl.to_i }
      out[:resources][:action_surge] = { uses:, recharge: (as[:recharge] || 'SR'), limit_one_per_turn: !!as[:limit_one_per_turn] }
    end
    if ind = fr[:indomitable]
      uses = 0
      (ind[:uses_by_level] || {}).each { |lvl,u| uses = [uses, u.to_i].max if level >= lvl.to_i }
      out[:resources][:indomitable] = { uses:, recharge: (ind[:recharge] || 'LR') }
    end

    # --- Monk: Martial Arts / Ki ---
    if ma = fr[:martial_arts]
      die = 'd4'
      (ma[:die_by_level] || {}).each { |lvl, d| die = d if level >= lvl.to_i }
      out[:choices][:martial_arts_die] = die
    end
    if ki = fr[:ki]
      points = (ki[:points_by_level] == :monk_level) ? mnk_lvl : 0
      out[:resources][:ki] = { uses: points, recharge: (ki[:recharge] || 'SR') }
    end
    out[:proficiency_overrides][:evasion] = true if fr[:evasion].present? && level >= (fr[:evasion][:available_at] || 7).to_i
    if pob = fr[:purity_of_body]
      out[:choices][:purity_of_body] = { immune: Array(pob[:immune]) } if level >= pob[:available_at].to_i
    end

    # --- Paladin: Auras / recursos ---
    if aop = fr[:aura_of_protection]
      if level >= aop[:available_at].to_i
        radius = 0
        (aop[:radius_ft_by_level] || {}).each { |lvl,r| radius = [radius, r.to_i].max if level >= lvl.to_i }
        out[:auras][:protection] = { radius_ft: radius, add_mod_to: 'saving_throws', mod: 'CHA' }
      end
    end
    if aoc = fr[:aura_of_courage]
      if level >= aoc[:available_at].to_i
        radius = 0
        (aoc[:radius_ft_by_level] || {}).each { |lvl,r| radius = [radius, r.to_i].max if level >= lvl.to_i }
        out[:auras][:courage] = { radius_ft: radius, immune: ['frightened'] }
      end
    end
    if ds = fr[:divine_sense]
      out[:resources][:divine_sense] = { uses: ds[:uses_per_long_rest].to_s, recharge: 'LR' }
    end
    if loh = fr[:lay_on_hands]
      out[:resources][:lay_on_hands] = { pool: loh[:pool_per_long_rest].to_s, recharge: 'LR' }
    end

    # --- Ranger: flags passivas ---
    # (já sinalizadas no bloco, sem cálculo adicional aqui)

    # --- Rogue: Sneak Attack etc. ---
    if sa = fr[:sneak_attack]
      dice = 0
      (sa[:dice_by_level] || {}).each { |lvl, n| dice = [dice, n.to_i].max if level >= lvl.to_i }
      out[:choices][:sneak_attack] = { dice:, die: (sa[:die] || 'd6') }
    end
    out[:proficiency_overrides][:reliable_talent] = { d20_min_floor: 10 } if fr[:reliable_talent]&.dig(:available_at).to_i <= level
    out[:proficiency_overrides][:slippery_mind] = { grant_save_proficiency: 'WIS' } if fr[:slippery_mind]&.dig(:available_at).to_i <= level
    out[:proficiency_overrides][:uncanny_dodge] = true if fr[:uncanny_dodge]&.dig(:available_at).to_i <= level
    out[:proficiency_overrides][:elusive] = true if fr[:elusive]&.dig(:available_at).to_i <= level

    # --- Sorcerer ---
    if sp = fr[:sorcery_points]
      pts = 0
      (sp[:by_level] || {}).each { |lvl,v| pts = [pts, v.to_i].max if level >= lvl.to_i }
      out[:resources][:sorcery_points] = { uses: pts, recharge: (sp[:recharge] || 'LR') }
    end
    if mm = fr[:metamagic]
      map = {}
      (mm[:choices_by_level] || {}).each { |lvl, n| map[lvl.to_s] = n.to_i if level >= lvl.to_i }
      out[:choices][:metamagic] = map if map.any?
    end

    # --- Warlock ---
    if pm = fr[:pact_magic]
      slots = 0
      slot_level = 1
      (pm[:slots_by_level] || {}).each { |lvl, n| slots = [slots, n.to_i].max if level >= lvl.to_i }
      (pm[:slot_level_by_level] || {}).each { |lvl, sl| slot_level = [slot_level, sl.to_i].max if level >= lvl.to_i }
      out[:resources][:pact_slots] = { count: slots, slot_level: slot_level, recharge: (pm[:recharge] || 'SR') }
    end
    if inv = fr[:eldritch_invocations]
      cnt = 0
      (inv[:count_by_level] || {}).each { |lvl, n| cnt = [cnt, n.to_i].max if level >= lvl.to_i }
      out[:choices][:eldritch_invocations] = { count: cnt }
    end
    if ma = fr[:mystic_arcanum]
      grants = {}
      (ma[:grants] || {}).each { |lvl, row| grants[lvl.to_s] = row if level >= lvl.to_i }
      out[:choices][:mystic_arcanum] = grants if grants.any?
    end

    # --- Wizard ---
    if ar = fr[:arcane_recovery]
      out[:resources][:arcane_recovery] = {
        once_per_day: !!ar[:once_per_day],
        requires_short_rest: !!ar[:requires_short_rest],
        max_slot_levels_sum: ar[:max_slot_levels_sum].to_s,
        slot_level_cap_by_level: ar[:slot_level_cap_by_level]
      }
    end
    if sb = fr[:spellbook_progression]
      out[:choices][:spellbook_learn_on_level_up] = sb[:learn_on_level_up].to_i if sb[:learn_on_level_up].to_i > 0
    end

    # --- Spellcasting meta (eco) ---
    %i[spellcasting pact_magic].each do |k|
      next unless fr[k].present?
      out[:spellcasting_meta][k] = fr[k]
    end

    # NOVO (3.1): Merge de recursos declarados diretamente na classe
    if rule[:resources].is_a?(Hash)
      rule[:resources].each do |key, conf|
        out[:resources][key] ||= {}
        out[:resources][key].merge!(conf)
      end
    end

    # NOVO (3.2+): Cálculo específico para Petiscos (Cozinheiro) + Aceitando Pedidos
    if rule[:id].to_s == 'cozinheiro'
      con = (ability_scores[:CON] || ability_scores['CON']).to_i
      con_mod = ((con - 10) / 2.0).floor
      prof = 2 + ((level - 1) / 4) # bônus de prof padrão 5e
      base_uses = [1, con_mod].max

      # Aceitando Pedidos (feature_rules) — a partir do 7º: petiscos adicionais = mod CON
      # No 11º, também em descanso curto (mantemos SR/LR no recurso e registramos metadado)
      extra_from_orders = (level >= 7 ? [0, con_mod].max : 0)
      total_uses = base_uses + extra_from_orders

      out[:resources][:snacks] = {
        uses: total_uses,
        recharge: 'SR/LR',
        dc: 8 + prof + con_mod,
        notes: 'Petiscos: CD = 8 + Prof + CON',
        metadata: {
          base_uses: base_uses,
          extra_from_taking_orders: extra_from_orders,
          short_rest_extra_enabled_at: 11
        }
      }
    end

    out
  end

  # === Novo apply com derived (não quebra o apply existente) ===
  def self.apply_with_derived(selection)
    base = apply(selection)
    derived = derive_feature_rules(
      rule: find(selection[:klass_id]),
      level: selection[:level].to_i.nonzero? || 1,
      picks: selection[:picks] || {},
      ability_scores: selection[:picks].to_h[:ability_scores] || {},
      equipment: selection[:picks].to_h[:equipment] || {}
    )
    base.merge(derived_rules: derived)
  end

  # === CLASS_RULES melhorado (patches + feature_rules) ===
  CLASS_RULES = {
    barbarian: {
      id: 'barbarian', name: 'Bárbaro', hit_die: 'd12',
      primary_abilities: %w[STR CON], saving_throws: %w[STR CON],
      armor_proficiencies: %w[leve média escudos],
      weapon_proficiencies: ['armas simples','armas marciais'],
      tool_proficiencies: [],
      skill_proficiencies: { choose: 2, options: ['Lidar com Animais','Atletismo','Intimidação','Natureza','Percepção','Sobrevivência'] },
      features_level1: ['Fúria','Defesa sem Armadura'],
      subclass: {
        choose_level: 3,
        options: {
          berserker: { id: 'berserker', name: 'Caminho do Furioso' },
          totem: { id: 'totem', name: 'Caminho do Guerreiro Totêmico' },
          # Path of the Zealot (XGtE) — adicionado para alinhar com o front
          # (BARBARIAN_ZEALOT em subclassFeatures.ts).
          zealot: { id: 'zealot', name: 'Caminho do Zelote' },
          :'barbaro-cicatrizes-runicas' => { id: 'barbaro-cicatrizes-runicas', name: 'Caminho do Bárbaro das Cicatrizes Rúnicas' },
          :'desistente' => { id: 'desistente', name: 'Caminho do Desistente' },
          :'furioso-imortal' => { id: 'furioso-imortal', name: 'Caminho do Furioso Imortal' },
          :'guerreiro-urso' => { id: 'guerreiro-urso', name: 'Caminho do Guerreiro Urso' },
          :'protetor-tribal' => { id: 'protetor-tribal', name: 'Caminho do Protetor Tribal' },
          :'raivoso-elemental' => { id: 'raivoso-elemental', name: 'Caminho do Raivoso Elemental' },
        },
      },
      resources: { rage: { uses_by_level: {1=>2, 3=>3, 6=>4, 12=>5, 17=>6}, recharge: 'LR' } },
      required_choices_at_level: {},
      starting_gold: '2d4x10',
      starting_equipment: {
        choices: [
          { choose: 1, options: ['greataxe', 'martial-melee:any'] },
          { choose: 1, options: ['handaxe:2', 'simple:any'] },
          { choose: 1, options: ['explorer-pack','dungeoneer-pack'] }
        ],
        extras: ['javelin:4']
      },
      feature_rules: {
        unarmored_defense: { level: 1, formula: "10 + DEX + CON", allows_shield: true },
        fast_movement:     { level: 5, add: 3, unless: { armor_category: 'heavy' } },
        brutal_critical:   { scaling_by_level: { 9=>1, 13=>2, 17=>3 } },
        indomitable_might: { level: 18 },
        primal_champion:   { level: 20, fixed: { STR: 4, CON: 4 }, caps: { STR: 24, CON: 24 } },
        ability_score_improvement: { levels: [4,8,12,16,19] }
      }
    },

    bard: {
      id: 'bard', name: 'Bardo', hit_die: 'd8',
      primary_abilities: %w[CHA], saving_throws: %w[DEX CHA],
      armor_proficiencies: %w[leve],
      weapon_proficiencies: ['armas simples','bestas de mão','espadas longas','rapieiras','espadas curtas'],
      tool_proficiencies: { instruments: { choose: 3, choices: INSTRUMENTS } },
      skill_proficiencies: { choose: 3, options: :any },
      features_level1: ['Inspiração Bárdica (d6)','Conjuração'],
      subclass: {
        choose_level: 3,
        options: {
          lore: { id: 'lore', name: 'Colégio do Conhecimento' },
          valor: { id: 'valor', name: 'Colégio da Bravura' },
          # College of Glamour (XGtE) — adicionado para alinhar com o front
          # (BARD_GLAMOUR em subclassFeatures.ts).
          :'colegio-do-glamour' => { id: 'colegio-do-glamour', name: 'Colégio do Glamour' },
          :'colegio-busca-cancao' => { id: 'colegio-busca-cancao', name: 'Colégio da Busca da Canção' },
          :'colegio-comedia' => { id: 'colegio-comedia', name: 'Colégio da Comédia' },
          :'colegio-fortuna' => { id: 'colegio-fortuna', name: 'Colégio da Fortuna' },
          :'colegio-quietude' => { id: 'colegio-quietude', name: 'Colégio da Quietude' },
          :'colegio-pavor' => { id: 'colegio-pavor', name: 'Colégio do Pavor' },
          :'colegio-virtuosismo' => { id: 'colegio-virtuosismo', name: 'Colégio do Virtuosismo' },
        },
      },
      starting_gold: '5d4x10',
      starting_equipment: {
        choices: [
          { choose: 1, options: ['rapieira','espada-longa','simple:any'] },
          { choose: 1, options: ['pacote-diplomata','pacote-artista'] },
          { choose: 1, options: INSTRUMENTS }
        ],
        extras: ['armadura-couro','adaga']
      },
      spellcasting: {
        type: 'full', casting_ability: 'CHA', preparation: 'known',
        cantrips_known_at_1: 2, spells_known_at_1: 4,
        ritual: 'if_known', focus: 'instrument', list: 'bard'
      },
      required_choices_at_level: {
        3  => { expertise_skills: { choose: 2 } },
        10 => { expertise_skills: { choose: 2 }, learn_any_class_spells: { choose: 2 } },
        14 => { learn_any_class_spells: { choose: 2 } },
        18 => { learn_any_class_spells: { choose: 2 } }
      },
      feature_rules: {
        bardic_inspiration: { level: 1 },
        jack_of_all_trades: { level: 2 },
        song_of_rest:       { level: 2 },
        expertise:          { gains: [{ level: 3, count: 2 }, { level: 10, count: 2 }] },
        magical_secrets:    { gains: [{ level: 10, learn: 2 }, { level: 14, learn: 2 }, { level: 18, learn: 2 }] },
        spellcasting:       { ability: 'CHA', mode: 'known', ritual: 'if_known', focus: 'instrument', list: 'bard' },
        ability_score_improvement: { levels: [4,8,12,16,19] }
      }
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
          :'dominio-agua' => { id: 'dominio-agua', name: 'Domínio da Água' },
          :'dominio-criacao' => { id: 'dominio-criacao', name: 'Domínio da Criação' },
          :'dominio-mente' => { id: 'dominio-mente', name: 'Domínio da Mente' },
          :'dominio-terra' => { id: 'dominio-terra', name: 'Domínio da Terra' },
          :'dominio-ar' => { id: 'dominio-ar', name: 'Domínio do Ar' },
          :'dominio-tempo' => { id: 'dominio-tempo', name: 'Domínio do Tempo' },
          :'dominio-do-conhecimento' => { id: 'dominio-do-conhecimento', name: 'Domínio do Conhecimento' },
          :'dominio-da-vida' => { id: 'dominio-da-vida', name: 'Domínio da Vida' },
          :'dominio-da-luz' => { id: 'dominio-da-luz', name: 'Domínio da Luz' },
          :'dominio-da-natureza' => { id: 'dominio-da-natureza', name: 'Domínio da Natureza' },
          :'dominio-da-tempestade' => { id: 'dominio-da-tempestade', name: 'Domínio da Tempestade' },
          :'dominio-da-trapaca' => { id: 'dominio-da-trapaca', name: 'Domínio da Enganação' },
          :'dominio-da-guerra' => { id: 'dominio-da-guerra', name: 'Domínio da Guerra' },
        },
      },
      spellcasting: {
        type: 'full', casting_ability: 'WIS', preparation: 'prepared',
        cantrips_known_at_1: 3, spells_known_at_1: nil,
        ritual: 'if_prepared', focus: 'holy_symbol', list: 'cleric'
      },
      required_choices_at_level: {},
      starting_gold: '5d4x10',
      starting_equipment: {
        choices: [
          { choose: 1, options: ['mace','warhammer'] },
          { choose: 1, options: ['scale-mail','leather','chain-mail'] },
          { choose: 1, options: ['light-crossbow:1+bolts:20','simple:any'] },
          { choose: 1, options: ['priest-pack','explorer-pack'] }
        ],
        extras: ['shield','holy-symbol']
      },
      feature_rules: {
        spellcasting:       { ability: 'WIS', mode: 'prepared', ritual: 'if_prepared', focus: 'holy_symbol', list: 'cleric' },
        channel_divinity:   { recharge: 'SR', uses_by_level: { 2=>1, 6=>2, 18=>3 } },
        destroy_undead:     { cr_threshold_by_level: { 5=>0.5, 8=>1, 11=>2, 14=>3, 17=>4 } },
        divine_intervention:{ available_at: 10, auto_success_at: 20 },
        ability_score_improvement: { levels: [4,8,12,16,19] }
      }
    },

    druid: {
      id: 'druid', name: 'Druida', hit_die: 'd8',
      primary_abilities: %w[WIS], saving_throws: %w[INT WIS],
      armor_proficiencies: %w[leve média escudos],
      weapon_proficiencies: ['clavas','adagas','dardos','azagaias','maças','bordões','cimitarra','foices','fundas','lanças'],
      tool_proficiencies: ['Kit de Herbalismo'],
      skill_proficiencies: { choose: 2, options: ['Arcanismo','Lidar com Animais','Intuição','Medicina','Natureza','Percepção','Religião','Sobrevivência'] },
      features_level1: ['Conjuração','Druídico'],
      subclass: {
        choose_level: 2,
        options: {
          circulo_da_terra: { id: 'circulo-da-terra', name: 'Círculo da Terra' },
          circulo_da_lua: { id: 'circulo-da-lua', name: 'Círculo da Lua' },
          circulo_infestacao: { id: 'circulo-infestacao', name: 'Círculo da Infestação' },
          circulo_vida: { id: 'circulo-vida', name: 'Círculo da Vida' },
          circulo_fadas: { id: 'circulo-fadas', name: 'Círculo das Fadas' },
          circulo_feras: { id: 'circulo-feras', name: 'Círculo das Feras' },
          circulo_mundos: { id: 'circulo-mundos', name: 'Círculo dos Mundos' },
        },
      },
      spellcasting: {
        type: 'full', casting_ability: 'WIS', preparation: 'prepared',
        cantrips_known_at_1: 2, spells_known_at_1: nil,
        ritual: 'if_prepared', focus: 'druidic_focus', list: 'druid'
      },
      required_choices_at_level: {},
      starting_gold: '2d4x10',
      starting_equipment: {
        choices: [
          { choose: 1, options: ['shield','simple:any'] },
          { choose: 1, options: ['scimitar','simple-melee:any'] },
          { choose: 1, options: ['scholar-pack','explorer-pack'] }
        ],
        extras: ['leather','explorer-pack','druidic-focus']
      },
      feature_rules: {
        spellcasting:   { ability: 'WIS', mode: 'prepared', ritual: 'if_prepared', focus: 'druidic_focus', list: 'druid' },
        druidic:        { known: true },
        wild_shape:     { uses: 2, recharge: 'SR', cr_limit_by_level: { 2=>0.25, 4=>0.5, 8=>1 }, swim_at_level: 4, fly_at_level: 8 },
        armor_restriction: { forbid_metal_armor: true },
        ability_score_improvement: { levels: [4,8,12,16,19] }
      }
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
          eldritch_knight: { id: 'eldritch_knight', name: 'Cavaleiro Arcano', grants: { spellcasting: { type: 'third', casting_ability: 'INT', preparation: 'known', cantrips_known_at_1: 0, spells_known_at_1: 0, ritual: false, focus: 'arcane_focus', list: 'wizard', school_bias: %w[Abjuração Evocação] } } },
          atirador_inigualavel: { id: 'atirador_inigualavel', name: 'Atirador Inigualável' },
          cavaleiro_implacavel: { id: 'cavaleiro_implacavel', name: 'Cavaleiro Implacável' },
          defensor_dedicado: { id: 'defensor_dedicado', name: 'Defensor Dedicado' },
          kensai: { id: 'kensai', name: 'Kensai' },
          mestre_correntes: { id: 'mestre_correntes', name: 'Mestre das Correntes' },
          mestre_arremesso: { id: 'mestre_arremesso', name: 'Mestre do Arremesso' }
        }
      },
      required_choices_at_level: { 1 => { fighting_style: { choose: 1, options: FIGHTING_STYLES } } },
      starting_gold: '5d4x10',
      feature_rules: {
        fighting_style: {
          options: {
            'Defesa'=>{ ac_bonus: 1, requires_armor: true },
            'Arquearia'=>{ attack_bonus_ranged: 2 },
            'Duelos'=>{ damage_bonus_melee_one_handed: 2 },
            'Combate com Duas Armas'=>{ add_mod_to_offhand_damage: true },
            'Proteção'=>{ reaction_impose_disadvantage: true, requires_shield: true },
            'Grande Arma'=>{ reroll_damage_dice: [1,2], weapons: 'two_handed_or_versatile_melee' }
          }
        },
        second_wind: { recharge: 'SR', uses: 1, heal_formula: '1d10 + fighter_level' },
        action_surge: { recharge: 'SR', uses_by_level: { 2=>1, 17=>2 }, limit_one_per_turn: true },
        indomitable:  { recharge: 'LR', uses_by_level: { 9=>1, 13=>2, 17=>3 } },
        ability_score_improvement: { levels: [4,6,8,12,14,16,19] }
      }
    },

    monk: {
      id: 'monk', name: 'Monge', hit_die: 'd8',
      primary_abilities: %w[DEX WIS], saving_throws: %w[STR DEX],
      armor_proficiencies: [],
      weapon_proficiencies: ['armas simples','espadas curtas'],
      tool_proficiencies: { choose: 1, options: [:artisan_tools_any, :instrument_any] },
      skill_proficiencies: { choose: 2, options: ['Acrobacia','Atletismo','História','Intuição','Religião','Furtividade'] },
      features_level1: ['Defesa sem Armadura','Artes Marciais'],
      subclass: { choose_level: 3, options: {
        open_hand: { id: 'open_hand', name: 'Caminho da Mão Aberta' },
        shadow: { id: 'shadow', name: 'Caminho da Sombra' },
        four_elements: { id: 'four_elements', name: 'Caminho dos Quatro Elementos' },
        caminho_aco: { id: 'caminho_aco', name: 'Caminho do Aço' },
        caminho_mestre_bebado: { id: 'caminho_mestre_bebado', name: 'Caminho do Mestre Bêbado' },
        caminho_monge_tatuado: { id: 'caminho_monge_tatuado', name: 'Caminho do Monge Tatuado' },
        caminho_ninjuts: { id: 'caminho_ninjuts', name: 'Caminho do Ninjútsu' },
        caminho_punho_sagrado: { id: 'caminho_punho_sagrado', name: 'Caminho do Punho Sagrado' },
        caminho_sadhaka: { id: 'caminho_sadhaka', name: 'Caminho do Sadhaka' },
      } },
      required_choices_at_level: {},
      starting_gold: '5d4',
      feature_rules: {
        unarmored_defense: { level: 1, formula: "10 + DEX + WIS", allows_shield: false },
        martial_arts: { die_by_level: { 1=>'d4', 5=>'d6', 11=>'d8', 17=>'d10' }, finesse_for_monk_weapons_and_unarmed: true, bonus_unarmed_after_attack: true },
        ki: { points_by_level: :monk_level, recharge: 'SR' },
        unarmored_movement: { bonus_ft_by_level: { 2=>10, 6=>15, 10=>20, 14=>25, 18=>30 }, special_at_level: { 9=>['water_run','wall_run'] } },
        evasion: { available_at: 7 },
        purity_of_body: { available_at: 10, immune: ['poison','disease'] },
        ability_score_improvement: { levels: [4,8,12,16,19] }
      }
    },

    paladin: {
      id: 'paladin', name: 'Paladino', hit_die: 'd10',
      primary_abilities: %w[STR CHA], saving_throws: %w[WIS CHA],
      armor_proficiencies: %w[leve média pesada escudos],
      weapon_proficiencies: ['armas simples','armas marciais'],
      tool_proficiencies: [],
      skill_proficiencies: { choose: 2, options: ['Atletismo','Intuição','Intimidação','Medicina','Persuasão','Religião'] },
      features_level1: ['Sentido Divino','Imposição das Mãos'],
      subclass: {
        choose_level: 3,
        options: {
          devotion: { id: 'devotion', name: 'Juramento de Devoção' },
          ancients: { id: 'ancients', name: 'Juramento dos Anciões' },
          vengeance: { id: 'vengeance', name: 'Juramento de Vingança' },
          :'juramento-danacao' => { id: 'juramento-danacao', name: 'Juramento de Danação' },
          :'juramento-equilibrio' => { id: 'juramento-equilibrio', name: 'Juramento de Equilíbrio' },
          :'juramento-liberdade' => { id: 'juramento-liberdade', name: 'Juramento de Liberdade' },
          :'juramento-misericordia' => { id: 'juramento-misericordia', name: 'Juramento de Misericórdia' },
          :'juramento-ordenacao' => { id: 'juramento-ordenacao', name: 'Juramento de Ordenação' },
          :'juramento-pureza' => { id: 'juramento-pureza', name: 'Juramento de Pureza' },
        },
      },
      spellcasting: { type: 'half', casting_ability: 'CHA', preparation: 'prepared', cantrips_known_at_1: 0, spells_known_at_1: nil, ritual: 'if_prepared', focus: 'holy_symbol', list: 'paladin' },
      required_choices_at_level: { 2 => { fighting_style: { choose: 1, options: ['Defesa','Duelos','Proteção','Grande Arma'] } } },
      feature_rules: {
        spellcasting: { type: 'half', ability: 'CHA', mode: 'prepared', ritual: 'if_prepared', focus: 'holy_symbol', list: 'paladin' },
        fighting_style: {
          options: {
            'Defesa'=>{ ac_bonus: 1, requires_armor: true },
            'Duelos'=>{ damage_bonus_melee_one_handed: 2 },
            'Proteção'=>{ reaction_impose_disadvantage: true, requires_shield: true },
            'Grande Arma'=>{ reroll_damage_dice: [1,2], weapons: 'two_handed_or_versatile_melee' }
          }
        },
        divine_sense:     { uses_per_long_rest: "1 + CHA" },
        lay_on_hands:     { pool_per_long_rest: "5 * paladin_level" },
        # PHB Paladino: Canalizar Divindade ganho no nv 3, 1 uso, recarrega em
        # descanso curto ou longo. Diferente do clerigo, NAO escala em usos
        # (apenas adiciona opcoes via Juramento). Mantemos schema compativel
        # com derive_feature_rules (uses_by_level + recharge).
        channel_divinity: { recharge: 'SR', uses_by_level: { 3 => 1 } },
        aura_of_protection: { available_at: 6, radius_ft_by_level: { 6=>10, 18=>30 }, add_mod: { to: 'saving_throws', mod: 'CHA' } },
        aura_of_courage:    { available_at: 10, radius_ft_by_level: { 10=>10, 18=>30 }, immune: ['frightened'] },
        ability_score_improvement: { levels: [4,8,12,16,19] }
      }
    },

    ranger: {
      id: 'ranger', name: 'Patrulheiro', hit_die: 'd10',
      primary_abilities: %w[DEX WIS], saving_throws: %w[STR DEX],
      armor_proficiencies: %w[leve média escudos],
      weapon_proficiencies: ['armas simples','armas marciais'],
      tool_proficiencies: [],
      skill_proficiencies: { choose: 3, options: ['Lidar com Animais','Atletismo','Intuição','Investigação','Natureza','Percepção','Furtividade','Sobrevivência'] },
      features_level1: ['Inimigo Favorito','Explorador Nato'],
      subclass: {
        choose_level: 3,
        options: {
          hunter: { id: 'hunter', name: 'Caçador' },
          beast_master: { id: 'beast_master', name: 'Mestre das Bestas' },
          :'batedor' => { id: 'batedor', name: 'Batedor' },
          :'flagelo-dos-inimigos' => { id: 'flagelo-dos-inimigos', name: 'Flagelo dos Inimigos' },
          arqueiro_floresta_alta: { id: 'arqueiro_floresta_alta', name: 'Arqueiro da Floresta Alta' },
          guardiao_selvagem: { id: 'guardiao_selvagem', name: 'Guardião Selvagem' },
          rastreador_urbano: { id: 'rastreador_urbano', name: 'Rastreador Urbano' },
        },
      },
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
      },
      feature_rules: {
        spellcasting: { type: 'half', ability: 'WIS', mode: 'known', ritual: false, list: 'ranger' },
        fighting_style: {
          options: {
            'Defesa'=>{ ac_bonus: 1, requires_armor: true },
            'Arquearia'=>{ attack_bonus_ranged: 2 },
            'Duelos'=>{ damage_bonus_melee_one_handed: 2 },
            'Combate com Duas Armas'=>{ add_mod_to_offhand_damage: true }
          }
        },
        favored_enemy:     { track_advantage: true, knowledge_bonus: true },
        natural_explorer:  { ignore_difficult_terrain_travel: true, advantage_on_initiative_in_nat_env: true },
        primeval_awareness:{ available_at: 3 },
        ability_score_improvement: { levels: [4,8,12,16,19] }
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
      subclass: {
        choose_level: 3,
        options: {
          :'ladrao' => { id: 'ladrao', name: 'Ladrão' },
          :'assassino' => { id: 'assassino', name: 'Assassino' },
          :'trapaceiro-arcano' => {
            id: 'trapaceiro-arcano',
            name: 'Trapaceiro Arcano',
            grants: {
              spellcasting: {
                type: 'third',
                casting_ability: 'INT',
                preparation: 'known',
                cantrips_known_at_1: 0,
                spells_known_at_1: 0,
                ritual: false,
                focus: 'arcane_focus',
                list: 'wizard',
                school_bias: %w[Ilusão Encantamento],
              },
            },
          },
          :'cacador-de-tesouros' => { id: 'cacador-de-tesouros', name: 'Caçador de Tesouros' },
          :'dancarino-das-sombras' => { id: 'dancarino-das-sombras', name: 'Dançarino das Sombras' },
          :'face-fantasmagorica' => { id: 'face-fantasmagorica', name: 'Face Fantasmagórica' },
          :'lamina-invisivel' => { id: 'lamina-invisivel', name: 'Lâmina Invisível' },
          :'larapio-de-almas' => { id: 'larapio-de-almas', name: 'Larápio de Almas' },
          :'mimetizador' => { id: 'mimetizador', name: 'Mimetizador' },
        },
      },
      required_choices_at_level: {
        1 => { expertise_skills: { choose: 2, options: :selected_from_class_skills } },
        6 => { expertise_skills: { choose: 2, options: :selected_from_class_skills } }
      },
      starting_gold: '4d4x10',
      feature_rules: {
        expertise: { gains: [{ level: 1, count: 2 }, { level: 6, count: 2 }] },
        sneak_attack: {
          die: 'd6',
          dice_by_level: {
            1=>1,2=>1,3=>2,4=>2,5=>3,6=>3,7=>4,8=>4,9=>5,10=>5,11=>6,12=>6,13=>7,14=>7,15=>8,16=>8,17=>9,18=>9,19=>10,20=>10
          },
          once_per_turn: true, requires_advantage_or_ally: true, finesse_or_ranged: true
        },
        uncanny_dodge:    { available_at: 5 },
        evasion:          { available_at: 7 },
        reliable_talent:  { available_at: 11, d20_min_floor: 10 },
        slippery_mind:    { available_at: 15, grant_save_proficiency: 'WIS' },
        elusive:          { available_at: 18, attackers_cannot_have_advantage: true },
        stroke_of_luck:   { available_at: 20, recharge: 'LR' },
        ability_score_improvement: { levels: [4,8,10,12,16,19] }
      }
    },

    sorcerer: {
      id: 'sorcerer', name: 'Feiticeiro', hit_die: 'd6',
      primary_abilities: %w[CHA], saving_throws: %w[CON CHA],
      armor_proficiencies: [], weapon_proficiencies: ['adagas','dardos','fundas','bordões','bestas leves'],
      tool_proficiencies: [],
      skill_proficiencies: { choose: 2, options: ['Arcanismo','Enganação','Intuição','Intimidação','Persuasão','Religião'] },
      features_level1: ['Conjuração','Origem Feiticeira'],
      # SRD: draconic / wild. Expandido: subclass_overrides.yml (ids = api_index pós-apply, exceto SRD mapeado em SUBCLASS_ALIASES).
      subclass: {
        choose_level: 1,
        options: {
          draconic: { id: 'draconic', name: 'Linhagem Dracônica' },
          wild: { id: 'wild', name: 'Magia Selvagem' },
          :'feiticaria-da-espada' => { id: 'feiticaria-da-espada', name: 'Feitiçaria da Espada' },
          :'feiticaria-do-sangue' => { id: 'feiticaria-do-sangue', name: 'Feitiçaria do Sangue' },
          :'linhagem-elemental' => { id: 'linhagem-elemental', name: 'Linhagem Elemental' },
          :'origem-aberrante' => { id: 'origem-aberrante', name: 'Origem Aberrante' },
          :'origem-abissal' => { id: 'origem-abissal', name: 'Origem Abissal' },
          :'origem-mutavel' => { id: 'origem-mutavel', name: 'Origem Mutável' }
        }
      },
      spellcasting: { type: 'full', casting_ability: 'CHA', preparation: 'known', cantrips_known_at_1: 4, spells_known_at_1: 2, ritual: false, focus: 'arcane_focus', list: 'sorcerer' },
      # Kit 1.PoC + Kit 3: options agora resolvem via :metamagic (catálogo canônico).
      # validate_subset: true ativa o subset validator opt-in.
      # Backward-compat: aceita slugs (mm-careful), name_pt (Magia Cuidadosa),
      # name_en (Careful Spell) e aliases legados (Suturar Magia).
      required_choices_at_level: {
        3  => { metamagic: { choose: 2, options: :metamagic, validate_subset: true } },
        10 => { metamagic: { choose: 1, options: :metamagic, validate_subset: true } },
        17 => { metamagic: { choose: 1, options: :metamagic, validate_subset: true } }
      },
      feature_rules: {
        spellcasting: { ability: 'CHA', mode: 'known', ritual: false, focus: 'arcane_focus', list: 'sorcerer' },
        sorcery_points: {
          recharge: 'LR',
          by_level: { 1=>0,2=>2,3=>3,4=>4,5=>5,6=>6,7=>7,8=>8,9=>9,10=>10,11=>11,12=>12,13=>13,14=>14,15=>15,16=>16,17=>17,18=>18,19=>19,20=>20 }
        },
        metamagic: { choices_by_level: { 3=>2, 10=>1, 17=>1 } },
        flexible_casting: { enabled: true },
        ability_score_improvement: { levels: [4,8,12,16,19] }
      }
    },

    warlock: {
      id: 'warlock', name: 'Bruxo', hit_die: 'd8',
      primary_abilities: %w[CHA], saving_throws: %w[WIS CHA],
      armor_proficiencies: %w[leve], weapon_proficiencies: ['armas','simples'], tool_proficiencies: [],
      skill_proficiencies: { choose: 2, options: ['Arcanismo','Enganação','História','Intimidação','Investigação','Natureza','Religião'] },
      features_level1: ['Patrono Sobrenatural','Magia de Pacto'],
      # SRD: fiend/archfey/great_old_one. Extras: subclass_overrides.yml (patron-*).
      subclass: {
        choose_level: 1,
        options: {
          fiend: { id: 'fiend', name: 'O Ínfero' },
          archfey: { id: 'archfey', name: 'A Rainha/Príncipe das Fadas' },
          great_old_one: { id: 'great_old_one', name: 'O Grande Antigo' },
          'patrono-morte': { id: 'patrono-morte', name: 'A Morte' },
          'patrono-arcanjo-vingador': { id: 'patrono-arcanjo-vingador', name: 'O Arcanjo Vingador' },
          'patrono-espirito-heroico': { id: 'patrono-espirito-heroico', name: 'O Espírito Heroico' },
          'patrono-supragenio': { id: 'patrono-supragenio', name: 'O Supragênio' },
          'patrono-tita-caido': { id: 'patrono-tita-caido', name: 'O Titã Caído' },
          'patrono-vazio': { id: 'patrono-vazio', name: 'O Vazio' }
        }
      },
      spellcasting: { type: 'pact', casting_ability: 'CHA', preparation: 'known', cantrips_known_at_1: 2, spells_known_at_1: 2, ritual: false, focus: 'arcane_focus', list: 'warlock' },
      required_choices_at_level: {
        2 => { invocations: { choose: 2, options: :eldritch_invocations, validate_subset: true } },
        3 => { pact_boon: { choose: 1, options: ['Pacto da Lâmina','Pacto da Corrente','Pacto do Tomo'] } }
      },
      feature_rules: {
        pact_magic: {
          ability: 'CHA', mode: 'known', list: 'warlock', recharge: 'SR',
          slots_by_level: {
            1=>1,2=>2,3=>2,4=>2,5=>2,6=>2,7=>2,8=>2,9=>2,10=>2,11=>3,12=>3,13=>3,14=>3,15=>3,16=>3,17=>4,18=>4,19=>4,20=>4
          },
          slot_level_by_level: {
            1=>1,2=>1,3=>2,4=>2,5=>3,6=>3,7=>4,8=>4,9=>5,10=>5,11=>5,12=>5,13=>5,14=>5,15=>5,16=>5,17=>5,18=>5,19=>5,20=>5
          }
        },
        eldritch_invocations: {
          count_by_level: { 2=>2,3=>2,4=>2,5=>3,6=>3,7=>4,8=>4,9=>5,10=>5,11=>5,12=>6,13=>6,14=>7,15=>7,16=>8,17=>8,18=>8,19=>9,20=>9 }
        },
        pact_boon: { choose_at_level: 3, options: ['Pacto da Lâmina','Pacto da Corrente','Pacto do Tomo'] },
        mystic_arcanum: { grants: { 11=>{ level: 6, uses: 1 }, 13=>{ level: 7, uses: 1 }, 15=>{ level: 8, uses: 1 }, 17=>{ level: 9, uses: 1 } } },
        ability_score_improvement: { levels: [4,8,12,16,19] }
      }
    },

    wizard: {
      id: 'wizard', name: 'Mago', hit_die: 'd6',
      primary_abilities: %w[INT], saving_throws: %w[INT WIS],
      armor_proficiencies: [], weapon_proficiencies: ['adagas','dardos','fundas','bordões','bestas leves'], tool_proficiencies: [],
      skill_proficiencies: { choose: 2, options: ['Arcanismo','História','Intuição','Investigação','Medicina','Religião'] },
      features_level1: ['Conjuração','Recuperação Arcana'],
      subclass: {
        choose_level: 2,
        options: {
          :'escola-de-abjuracao' => { id: 'escola-de-abjuracao', name: 'Escola de Abjuração' },
          :'escola-de-adivinhacao' => { id: 'escola-de-adivinhacao', name: 'Escola de Adivinhação' },
          :'escola-de-conjuracao' => { id: 'escola-de-conjuracao', name: 'Escola de Conjuração' },
          :'escola-de-encantamento' => { id: 'escola-de-encantamento', name: 'Escola de Encantamento' },
          :'escola-de-evocacao' => { id: 'escola-de-evocacao', name: 'Escola de Evocação' },
          :'escola-de-ilusao' => { id: 'escola-de-ilusao', name: 'Escola de Ilusão' },
          :'escola-de-necromancia' => { id: 'escola-de-necromancia', name: 'Escola de Necromancia' },
          :'escola-de-transmutacao' => { id: 'escola-de-transmutacao', name: 'Escola de Transmutação' },
          :'arquearia-arcana' => { id: 'arquearia-arcana', name: 'Arquearia Arcana' },
          :'iniciacao-demonologia' => { id: 'iniciacao-demonologia', name: 'Iniciação em Demonologia' },
          :'maestria-alquimica' => { id: 'maestria-alquimica', name: 'Maestria Alquímica' },
          :'maestria-dos-automatos' => { id: 'maestria-dos-automatos', name: 'Maestria dos Autômatos' },
          :'navegacao-planar' => { id: 'navegacao-planar', name: 'Navegação Planar' },
          :'teurgia-mistica' => { id: 'teurgia-mistica', name: 'Teurgia Mística' },
        },
      },
      spellcasting: { type: 'full', casting_ability: 'INT', preparation: 'prepared', cantrips_known_at_1: 3, spells_known_at_1: 6, ritual: 'spellbook', focus: 'arcane_focus', list: 'wizard' },
      required_choices_at_level: {},
      feature_rules: {
        spellcasting: { ability: 'INT', mode: 'prepared', ritual: 'spellbook', focus: 'arcane_focus', list: 'wizard' },
        spellbook_progression: { learn_on_level_up: 2, copy_from_scrolls: true },
        arcane_recovery: {
          once_per_day: true, requires_short_rest: true,
          max_slot_levels_sum: 'ceil(wizard_level / 2)',
          slot_level_cap_by_level: { 1=>1, 3=>2, 5=>3, 7=>4, 9=>5 }
        },
        ability_score_improvement: { levels: [4,8,12,16,19] }
      }
    },

    cozinheiro: {
      id: 'cozinheiro', name: 'Cozinheiro', hit_die: 'd8',
      primary_abilities: %w[CON DEX],
      saving_throws: %w[CON CHA],

      armor_proficiencies: %w[leve média],
      weapon_proficiencies: ['armas simples','bestas leves','espadas curtas','espadas longas','rapieiras'],
      tool_proficiencies: ['Ferramentas de Artesão (Cozinheiro)'],

      skill_proficiencies: {
        choose: 3,
        options: ['Lidar com Animais','Arcanismo','Atletismo','Medicina','Natureza','Atuação','Persuasão','Prestidigitação','Sobrevivência']
      },

      features_level1: ['Bolsa de Cozinheiro','Petiscos','Sais Aromáticos'],

      subclass: {
        choose_level: 3,
        options: {
          # Canônicos do PDF (O_Cozinheiro_-_Classe.pdf — Sam Grierson)
          'sous-chef':              { id: 'sous-chef',              name: 'Sous Chef' },
          'sargento-alimentar':     { id: 'sargento-alimentar',     name: 'Sargento Alimentar' },
          'mestre-cuca':            { id: 'mestre-cuca',            name: 'Mestre-Cuca' },
          'mestre-cervejeiro':      { id: 'mestre-cervejeiro',      name: 'Mestre Cervejeiro' },
          'amassador-de-monstros':  { id: 'amassador-de-monstros',  name: 'Amassador de Monstros' },
          # Homebrew Lafiga
          'doceiro-encantado':      { id: 'doceiro-encantado',      name: 'Doceiro Encantado' }
        }
      },

      spellcasting: nil,

      resources: {
        snacks: {
          uses: 'Mod. CON por descanso curto ou longo',
          recharge: 'SR/LR',
          dc_formula: '8 + Prof + CON'
        }
      },

      feature_rules: {
        cook: {
          snacks: {
            enabled: true,
            ability: 'CON',
            recharge: 'SR/LR',
            dc_formula: '8 + Prof + CON',
            feed_action: 'action',
            one_active_per_creature: true,
            expires_when_removed_seconds: 6,
            known_by_level: {
              1=>3, 2=>3, 3=>4, 4=>5, 5=>6,
              6=>7, 7=>8, 8=>9, 9=>10, 10=>11,
              11=>12, 12=>12, 13=>13, 14=>13, 15=>14,
              16=>14, 17=>14, 18=>15, 19=>15, 20=>15
            }
          },

          aromatic_salts: {
            available_at: 1,
            repeat_saves_against: %w[charmed frightened],
            upgrades_at: {
              7  => { add: ['stunned'] },
              13 => { add: ['paralyzed'] }
            }
          },

          cook_bag: {
            available_at: 1,
            preserve_snacks: true,
            replenish_interval_days: 30,
            replenish_methods: [
              { type: 'buy', cost_gp: 10, time_hours: 0 },
              { type: 'forage', time_hours: 8 }
            ],
            recreate_if_lost: { cost_gp: 100, time_hours: 8 }
          },

          mise_en_place: {
            available_at: 2,
            suggested_tool_bonus: 1
          },

          expertise: {
            allow_tools: true,
            gains: [
              { level: 2, count: 2 },
              { level: 9, count: 2 }
            ]
          },

          rotund_reflection: {
            available_at: 4,
            trigger: 'hit_by_melee',
            size_cap: 'Large',
            range_m: 1.5,
            save: { ability: 'DEX', dc: 'snack_dc' },
            on_fail: { speed_to_0: true, choose: ['push_3m','prone'] }
          },

          taking_orders: {
            available_at: 7,
            extra_snacks: 'CON',
            extra_requires_no_prereq: true,
            short_rest_enabled_at: 11
          },

          ostrich_stomach: {
            available_at: 9,
            immune_conditions: ['poisoned'],
            immune_sources: ['ingested_poisons']
          },

          soul_of_food: {
            available_at: 15,
            create_food_and_water: { uses: 1, recharge: 'LR', tasty: true, non_perishable_days: 7 },
            conjure_ingredients_when_out: true
          },

          comforting_meal: {
            available_at: 17,
            double_snack_duration_if_shared_long_rest: true
          },

          leftovers: {
            available_at: 20,
            on_initiative_if_no_snacks: { conjure_one_snack: true }
          }
        },

        ability_score_improvement: { levels: [5,8,12,16,19] }
      },

      required_choices_at_level: {
        2 => { expertise_skills: { choose: 2 } },
        9 => { expertise_skills: { choose: 2 } }
      }
    }
  }.with_indifferent_access.freeze

  module ClassProficiencyAdapter
    module_function

    def slugify(str)
      str.to_s.downcase
         .tr("ÁÀÂÃÄáàâãäÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÕÖóòôõöÚÙÛÜúùûüÇç", "AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCc")
         .gsub(/[^\w]+/, '_')
         .gsub(/_+/, '_')
         .gsub(/^_|_$/, '')
    end

    ARMOR_GROUPS = {
      'leve'=>'light','light'=>'light',
      'média'=>'medium','media'=>'medium','medium'=>'medium',
      'pesada'=>'heavy','heavy'=>'heavy',
      'escudos'=>'shield','escudo'=>'shield','shield'=>'shield'
    }.freeze

    WEAPON_GROUPS = {
      'armas_simples'=>'simple','armas simples'=>'simple','simple'=>'simple','simples'=>'simple',
      'armas_marciais'=>'martial','armas marciais'=>'martial','martial'=>'martial','marciais'=>'martial'
    }.freeze

    ITEM_ALIASES = {
      # Armas
      'espada_longa'=>'longsword','espada-longa'=>'longsword','espadas_longas'=>'longsword',
      'espada_curta'=>'shortsword','espadas_curtas'=>'shortsword',
      'rapieira'=>'rapier',
      'bestas_de_mao'=>'hand_crossbow','besta_de_mao'=>'hand_crossbow',
      'besta_leve'=>'light_crossbow','besta-pesada'=>'heavy_crossbow',
      'arco_longo'=>'longbow','arco_curto'=>'shortbow',
      'clava'=>'club','maça'=>'mace','adaga'=>'dagger',
      'lança'=>'spear','lanca'=>'spear','azagaia'=>'javelin','machadinha'=>'handaxe',
      'martelo_de_guerra'=>'warhammer','picareta_de_guerra'=>'war_pick',
      'chicote'=>'whip','escimitarra'=>'scimitar','cajado'=>'quarterstaff',
      # Armaduras
      'couro'=>'leather','couro_batido'=>'studded_leather',
      'acolchoada'=>'padded',
      'cota_de_malha'=>'chain_mail','cota_de_anel'=>'ring_mail',
      'cota_de_talas'=>'splint','escudo'=>'shield'
    }.freeze

    def normalize_entry(entry)
      key = slugify(entry)
      ARMOR_GROUPS[key] || WEAPON_GROUPS[key] || ITEM_ALIASES[key] || key
    end

    def normalize_weapon_proficiencies(list)
      Array(list).map { |e| normalize_entry(e) }.uniq
    end

    def normalize_armor_proficiencies(list)
      Array(list).map { |e| normalize_entry(e) }.uniq
    end

    def normalize_all(class_rule)
      {
        armor: normalize_armor_proficiencies(class_rule[:armor_proficiencies]),
        weapons: normalize_weapon_proficiencies(class_rule[:weapon_proficiencies]),
        tools: class_rule[:tool_proficiencies] # já estruturado
      }
    end
  end

  # ---------------------------------------------------------------------------
  # 2) APPLY ATUALIZADO — devolve proficiências NORMALIZADAS
  # ---------------------------------------------------------------------------
  def self.apply(selection)
    rule = find(selection[:klass_id])
    raise ArgumentError, 'class not found' unless rule
    level = selection[:level].to_i.nonzero? || 1
    picks = selection[:picks] || {}

    # >>> Normalização de proficiências logo no início
    adapted = ClassProficiencyAdapter.normalize_all(rule)
    armor  = adapted[:armor]
    weapons = adapted[:weapons]
    tools   = adapted[:tools]

    # Instrumentos (Ex.: Bardo). Guard-rail: classes como Mago, Bárbaro, Paladino
    # têm `tool_proficiencies: []` (Array vazio). Sem o `is_a?(Hash)`, o
    # `Array#dig(:instruments, ...)` lança `TypeError: no implicit conversion of
    # Symbol into Integer` — engolido pelo `rescue StandardError` do
    # `ClassSummaryRebuilder` e fazia `class_summary` permanecer `{}`, deixando
    # a UI sem nenhuma proficiência (ver #BOOI 1405).
    tp = rule[:tool_proficiencies]
    if tp.is_a?(Hash) && tp.dig(:instruments, :choose)
      chosen = Array(selection[:instruments_selected]).map { |x| (x.is_a?(Hash) ? x[:name] : x).to_s }
      tools = tools.is_a?(Array) ? tools : Array(tools)
      tools << { instruments: chosen.first(tp[:instruments][:choose].to_i) }
    end

    # Perícias da classe (mesmo guard-rail do `tool_proficiencies` acima:
    # `skill_proficiencies` deveria ser Hash, mas se vier malformado como Array
    # de outra classe, evita o `Array#dig` quebrar.)
    sp = rule[:skill_proficiencies]
    sp = nil unless sp.is_a?(Hash)
    class_skills = if sp&.dig(:options) == :any
                     SKILLS_ALL
                   else
                     Array(sp&.dig(:options))
                   end
    skills_chosen = Array(selection[:skills_selected]).map { |x| (x.is_a?(Hash) ? x[:name] : x).to_s }
    skills = skills_chosen.first(sp&.dig(:choose).to_i)

    # Escolhas obrigatórias por nível (ex.: Estilo de Luta)
    required = (rule[:required_choices_at_level] || {}).select { |lvl, _| lvl.to_i <= level }
    required_summary = {}
    required.each do |_key_level, h|
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
    if rule.dig(:subclass, :choose_level).to_i > 0 && level >= rule.dig(:subclass, :choose_level).to_i
      sc_id = picks[:subclass_id] || picks['subclass_id']
      subclass = rule.dig(:subclass, :options, sc_id.to_sym) if sc_id
      unless subclass
        klass_record = Klass.find_by(api_index: rule[:id])
        if klass_record
          sub_klass_record = klass_record.sub_klasses.find_by(api_index: sc_id)
          if sub_klass_record
            subclass = { id: sub_klass_record.api_index, name: sub_klass_record.name, custom: true }
          end
        end
      end
    end

    {
      klass_id: rule[:id],
      name: rule[:name],
      hit_die: rule[:hit_die],
      primary_abilities: rule[:primary_abilities],
      saving_throws: rule[:saving_throws],
      armor_proficiencies: armor,        # << já normalizado
      weapon_proficiencies: weapons,     # << já normalizado
      tool_proficiencies: tools,         # << idem (com instrumentos escolhidos)
      skill_proficiencies_available: class_skills,
      skills_selected: skills,
      features_level1: rule[:features_level1],
      subclass: subclass,
      subclass_choose_level: rule.dig(:subclass, :choose_level),
      spellcasting: rule[:spellcasting],
      required_choices: required_summary,
      picks: picks
    }
  end

  # ---------------------------------------------------------------------------
  # 3) APPLY_WITH_DERIVED também normaliza e carrega picks
  # ---------------------------------------------------------------------------
  def self.apply_with_derived(selection)
    base = apply(selection) # já normalizado e com picks
    derived = derive_feature_rules(
      rule: find(selection[:klass_id]),
      level: selection[:level].to_i.nonzero? || 1,
      picks: selection[:picks] || {},
      ability_scores: selection[:picks].to_h[:ability_scores] || {},
      equipment: selection[:picks].to_h[:equipment] || {}
    )
    base.merge(derived_rules: derived)
  end

end
