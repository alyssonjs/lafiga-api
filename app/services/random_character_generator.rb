class RandomCharacterGenerator
  class << self
    def rand_abilities
      pool = [15, 14, 13, 12, 10, 8].shuffle
      { str: pool[0], dex: pool[1], con: pool[2], int: pool[3], wis: pool[4], cha: pool[5] }
    end

    def ensure_meta(sheet)
      d = sheet.metadata || {}
      d['class_choices'] ||= {}
      d['class_choices']['per_level'] ||= {}
      d
    end

    def write_choices!(sheet, _klass, level, picks: {})
      data = ensure_meta(sheet)
      lvl_key = level.to_s
      data['class_choices']['per_level'][lvl_key] ||= {}
      picks.each do |k, v|
        data['class_choices']['per_level'][lvl_key][k.to_s] = v
      end
      sheet.update!(metadata: data)
    end

    def choose_from(list, count)
      arr = Array(list).compact.map { |x| x.is_a?(Hash) ? (x[:name] || x['name']) : x }
      arr.sample([count.to_i, arr.size].min)
    end

    def pick_required_for_level!(sheet, klass, level)
      rule = ClassRules.find(klass.api_index) || {}
      required = (rule[:required_choices_at_level] || {})[level]
      return unless required

      picks = {}
      required.each do |key, conf|
        count = conf[:choose].to_i
        options = conf[:options]
        case options
        when :invocations_core
          pool = ['Agonizing Blast', 'Armor of Shadows', "Devil's Sight", 'Fiendish Vigor', 'Mask of Many Faces', 'Mire the Mind']
          picks[key] = choose_from(pool, count)
        when :selected_from_class_skills
          base = (sheet.metadata || {}).dig('class_choices', 'skills_selected') || []
          picks[key] = choose_from(base, count)
        else
          picks[key] = choose_from(options, count)
        end
      end
      write_choices!(sheet, klass, level, picks: picks)
    end

    def pick_level1_basics!(sheet, klass)
      rule = ClassRules.find(klass.api_index) || {}
      data = ensure_meta(sheet)
      # skills
      if rule.dig(:skill_proficiencies, :choose)
        choose = rule[:skill_proficiencies][:choose].to_i
        options = rule.dig(:skill_proficiencies, :options) == :any ? ClassRules.dictionaries[:skills_all] : (rule.dig(:skill_proficiencies, :options) || [])
        data['class_choices']['skills_selected'] = choose_from(options, choose)
      end
      # instruments (bard)
      tp = rule[:tool_proficiencies]
      inst = tp.is_a?(Hash) ? tp[:instruments] : nil
      if inst && inst[:choose].to_i > 0
        data['class_choices']['instruments_selected'] = choose_from(ClassRules.dictionaries[:instruments], inst[:choose])
      end
      sheet.update!(metadata: data)
    end

    def class_spell_ids_for(klass)
      SpellSource.where(source_type: 'Klass', source_id: klass.id).pluck(:spell_id)
    end

    def assign_initial_spells!(sheet, klass)
      sc = SpellRules.sc_for(klass, 1)
      return unless sc
      sk = sheet.sheet_klasses.find_by(klass_id: klass.id)
      return unless sk

      spell_list = Spell.where(id: class_spell_ids_for(klass))
      # Cantrips
      can_cnt = sc.cantrips_known.to_i
      if can_cnt > 0
        can_pool = spell_list.select { |sp| sp.level.to_i == 0 }
        can_pool.sample([can_cnt, can_pool.size].min).each do |sp|
          SpellLearningService.call(sheet_klass: sk, spell_id: sp.id)
        end
      end
      # Known (non-prepared) spells
      if sc.spells_known
        kn_cnt = sc.spells_known.to_i
        if kn_cnt > 0
          gate_level = SpellRules.gate_for(sheet, klass)
          pool = spell_list.where('level > 0 AND level <= ?', gate_level).to_a
          pool.sample([kn_cnt, pool.size].min).each do |sp|
            SpellLearningService.call(sheet_klass: sk, spell_id: sp.id)
          end
        end
      end
    end

    # Public API
    def generate_random_characters(count: 20, max_level_per_char: 5, user: nil)
      users = user ? [user] : User.all.to_a
      races = Race.all.to_a
      sub_races_by_race = SubRace.all.group_by(&:race_id)
      classes = Klass.all.to_a
      raise 'Precisa de users, races e classes nos seeds antes de gerar.' if users.empty? || races.empty? || classes.empty?

      created = []
      count.to_i.times do |i|
        current_user = users.sample
        klass = classes.sample
        race  = races.sample
        subrs = Array(sub_races_by_race[race.id])
        sub_race = subrs.sample

        # alvo até max_level_per_char ou o max definido em ClassLevel
        max_level = klass.class_levels.maximum(:level).to_i
        target_level = [max_level_per_char.to_i, [max_level, 1].max].min
        target_level = 1 if target_level < 1

        char = Character.create!(
          name: "Rnd-#{i + 1}-#{klass.name}",
          background: 'Gerado aleatoriamente',
          user_id: current_user.id,
          group_id: nil
        )

        creation = CharacterCreationService.new(
          character_id: char.id,
          race_id: race.id,
          sub_race_id: sub_race&.id,
          klass_id: klass.id,
          abilities: rand_abilities
        )
        creation.call
        sheet = creation.result

        # Background (se disponível)
        begin
          bg_key = %w[acolyte criminal soldier].sample
          BackgroundAssignmentService.call(sheet: sheet, key: bg_key)
        rescue NameError
        end

        # Picks iniciais e magias
        pick_level1_basics!(sheet, klass)
        assign_initial_spells!(sheet, klass)

        # Subclasse e level up
        chosen_sub_id = nil
        threshold = klass.subclass_level.to_i
        if threshold > 0
          chosen = SubKlass.where(klass_id: klass.id).to_a.sample
          chosen_sub_id = chosen&.id
          if chosen_sub_id && threshold == 1
            sk = sheet.sheet_klasses.find_by(klass_id: klass.id)
            sk.update!(sub_klass_id: chosen_sub_id)
          end
        end

        (2..target_level).each do |lvl|
          pick_required_for_level!(sheet, klass, lvl)
          sk = sheet.sheet_klasses.find_by(klass_id: klass.id)
          pass_sub = (chosen_sub_id && sk.sub_klass_id.blank? && threshold > 0 && lvl >= threshold) ? chosen_sub_id : nil
          LevelUpService.call(sheet_id: sheet.id, klass_id: klass.id, levels: 1, sub_klass_id: pass_sub, allow_spell_auto_fill: true)
        end

        created << char
      end
      created
    end

    def generate_one_per_class(max_level: 20, user: nil)
      current_user = user || User.first || User.create!(name: 'Smoke Tester', username: 'smoke', email: 'smoke@lafiga.com', password: 'secret', password_confirmation: 'secret')
      races = Race.all.to_a
      sub_by_race = SubRace.all.group_by(&:race_id)
      klasses = Klass.all.order(:id).to_a
      sub_by_klass = SubKlass.all.group_by(&:klass_id)
      raise 'Seeds insuficientes: faltam races/klasses.' if races.empty? || klasses.empty?

      created = []
      klasses.each do |klass|
        race = races.sample
        subr = (sub_by_race[race.id] || []).sample
        name = "Smoke-#{klass.name}-L#{max_level}"

        ch = Character.create!(name: name, background: 'Smoke test', user_id: current_user.id, group_id: nil)
        sheet = CharacterCreationService.call(character_id: ch.id, race_id: race.id, sub_race_id: (subr&.id), klass_id: klass.id, abilities: rand_abilities).result

        begin
          BackgroundAssignmentService.call(sheet: sheet, key: %w[acolyte criminal soldier].sample)
        rescue NameError
        end

        pick_level1_basics!(sheet, klass)
        pick_required_for_level!(sheet, klass, 1)

        sub_id = nil
        threshold = klass.subclass_level.to_i
        if threshold > 0
          chosen = (sub_by_klass[klass.id] || []).sample
          sub_id = chosen&.id
          if sub_id && threshold == 1
            sk = sheet.sheet_klasses.find_by(klass_id: klass.id)
            sk.update!(sub_klass_id: sub_id)
          end
        end

        assign_initial_spells!(sheet, klass)

        (2..max_level.to_i).each do |lvl|
          pick_required_for_level!(sheet, klass, lvl)
          sk = sheet.sheet_klasses.find_by(klass_id: klass.id)
          pass_sub = (sub_id && sk.sub_klass_id.blank? && threshold > 0 && lvl >= threshold) ? sub_id : nil
          LevelUpService.call(sheet_id: sheet.id, klass_id: klass.id, levels: 1, sub_klass_id: pass_sub, allow_spell_auto_fill: true)
        end

        created << sheet
      end
      created
    end
  end
end
