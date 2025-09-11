namespace :dnd do
  desc 'Gera 20 personagens aleatórios com raça, sub-raça, classe, subclasse, níveis e magias; valida consistência'
  task generate_characters: :environment do
    puts '== Gerando 20 personagens aleatórios =='

    count = (ENV['COUNT'] || 20).to_i
    max_level = (ENV['MAX_LEVEL'] || 5).to_i
    puts "== Gerando #{count} personagens (até nível #{max_level}) =="
    created = RandomCharacterGenerator.generate_random_characters(count: count, max_level_per_char: max_level)

    # Validação pós-geração
    puts "\n== Validação =="
    inconsistencies = []
    created.each do |ch|
      sheet = ch.sheet
      unless sheet
        inconsistencies << [ch.name, 'Sem Sheet']
        next
      end
      # sub-race pertence à race (model já valida, mas reportamos se houver)
      if sheet.sub_race_id && sheet.sub_race&.race_id != sheet.race_id
        inconsistencies << [ch.name, 'Sub-raça não pertence à raça']
      end

      sheet.sheet_klasses.each do |sk|
        klass = sk.klass
        # subclasse antes do nível
        if sk.sub_klass_id && klass.subclass_level.to_i > sk.level.to_i
          inconsistencies << [ch.name, "Subclasse antes do nível #{klass.subclass_level}"]
        end

        # spells conhecidas
        SheetKnownSpell.where(sheet_klass_id: sk.id).includes(:spell).each do |ks|
          source_ok = SpellSource.exists?(source_type: 'Klass', source_id: klass.id, spell_id: ks.spell_id)
          gate_ok = SpellRules.can_learn_spell?(sk, ks.spell)
          inconsistencies << [ch.name, "Known spell inválida: #{ks.spell.name}"] unless source_ok && gate_ok
        end
      end

      # preparadas
      SheetPreparedSpell.where(sheet_id: sheet.id).includes(:spell).each do |ps|
        # Para simplicidade, assumimos origem de classe
        # descobrir a classe preparada pelo spellcasting ability (wizard no exemplo)
        klass = sheet.sheet_klasses.joins(:klass).map(&:klass).find { |k| k.api_index == 'wizard' }
        next unless klass
        sk = sheet.sheet_klasses.find_by(klass_id: klass.id)
        source_ok = SpellSource.exists?(source_type: 'Klass', source_id: klass.id, spell_id: ps.spell_id)
        limit = SpellRules.prepared_limit_for(sheet, klass)
        count = SheetPreparedSpell.where(sheet_id: sheet.id, auto: false).count
        gate_ok = SpellRules.can_learn_spell?(sk, ps.spell)
        inconsistencies << [ch.name, "Prepared spell inválida: #{ps.spell.name}"] unless source_ok && gate_ok
        inconsistencies << [ch.name, "Excesso de preparadas (#{count}/#{limit})"] if count > limit
      end
    end

    if inconsistencies.empty?
      puts 'Sem inconsistências encontradas.'
    else
      puts "Inconsistências encontradas:"; inconsistencies.each { |n,m| puts " - #{n}: #{m}" }
    end

    puts "\nConcluído."
  end

  desc 'Analisa consistência de personagens existentes com base nas regras de 5e e imprime um relatório'
  task analyze_characters: :environment do
    puts '== Analisando personagens existentes =='
    report = []
    Character.includes(sheet: [:sub_race, :race, { sheet_klasses: :klass }]).find_each do |ch|
      next unless ch.sheet
      sheet = ch.sheet
      errors = []
      if sheet.sub_race_id && sheet.sub_race&.race_id != sheet.race_id
        errors << 'Sub-raça não pertence à raça'
      end
      # proficiência coerente com nível total (não persistimos bonus, calculamos para referência)
      total_level = CharacterRules.total_level(sheet)
      prof = CharacterRules.proficiency_bonus(total_level)

      sheet.sheet_klasses.each do |sk|
        klass = sk.klass
        if sk.sub_klass_id && klass.subclass_level.to_i > sk.level.to_i
          errors << "Subclasse antes do nível #{klass.subclass_level}"
        end

        # Known vs allowed (se houver spells_known na tabela para o nível)
        sc = SpellRules.sc_for(klass, sk.level)
        if sc
          # validar magias conhecidas (nível > 0)
          if sc.spells_known
            known_count = SheetKnownSpell.where(sheet_klass_id: sk.id).joins(:spell).where('spells.level > 0').count
            if known_count > sc.spells_known.to_i
              errors << "Known spells acima do permitido (#{known_count}/#{sc.spells_known})"
            end
          end
          # validar cantrips conhecidos (nível == 0)
          if sc.cantrips_known
            cantrip_count = SheetKnownSpell.where(sheet_klass_id: sk.id).joins(:spell).where('spells.level = 0').count
            if cantrip_count > sc.cantrips_known.to_i
              errors << "Cantrips acima do permitido (#{cantrip_count}/#{sc.cantrips_known})"
            end
          end
        end
      end

      # Prepared para classes prepared (ex.: wizard)
      sheet.sheet_klasses.each do |sk|
        klass = sk.klass
        next unless %w[cleric druid wizard paladin].include?(klass.api_index)
        limit = SpellRules.prepared_limit_for(sheet, klass)
        non_auto = SheetPreparedSpell.where(sheet_id: sheet.id, auto: false).count
        if non_auto > limit
          errors << "Prepared spells acima do limite (#{non_auto}/#{limit})"
        end
      end

      report << { character: ch.name, level: total_level, proficiency: prof, errors: errors }
    end

    path = Rails.root.join('tmp', 'dnd_character_report.json')
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(report))
    puts "Relatório salvo em #{path}"

    issues = report.select { |r| r[:errors].present? }
    if issues.empty?
      puts 'Sem inconsistências encontradas.'
    else
      puts 'Inconsistências:'
      issues.each do |r|
        puts "- #{r[:character]} (Nível #{r[:level]}):"
        r[:errors].each { |e| puts "   • #{e}" }
      end
    end
  end
end
