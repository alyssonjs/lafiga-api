namespace :dnd do
  namespace :smoke do
    desc 'Cria 1 personagem por classe até o nível 20 com raça/sub-raça/background aleatórios, preenche escolhas obrigatórias e valida.'
    task one_per_class: :environment do
      max_level = (ENV['MAX_LEVEL'] || 20).to_i
      puts "== Smoke: 1 por classe até o nível #{max_level} =="

      user = User.first || User.create!(name: 'Smoke Tester', username: 'smoke', email: 'smoke@example.com', password: 'secret', password_confirmation: 'secret')
      created = RandomCharacterGenerator.generate_one_per_class(max_level: max_level, user: user)

      # Validação rápida
      issues = []
      created.each do |sheet|
        sheet.reload
        sheet.sheet_klasses.each do |sk|
          klass = sk.klass
          guard = LevelUpGuardService.call(sheet: sheet, klass: klass)
          unless guard.success?
            issues << [sheet.character&.name, klass.name, guard.errors.full_messages]
          end
          # Fighter: estilo de luta presente
          if klass.api_index == 'fighter'
            fs = (sheet.metadata || {}).dig('class_choices','per_level','1','fighting_style')
            issues << [sheet.character&.name, 'Fighter', ['Fighting Style ausente no nível 1']] if fs.blank?
          end
          # Barbarian: recursos de fúria
          if klass.api_index == 'barbarian'
            rage = (sheet.metadata || {}).dig('resources','rage','uses').to_i
            issues << [sheet.character&.name, 'Barbarian', ['Pontos de Fúria não atribuídos']] if rage <= 0
          end
        end
        # Background associado
        bg = (sheet.metadata || {})['background_summary']
        issues << [sheet.character&.name, 'Background', ['Background não associado']] if bg.blank?
      end

      if issues.empty?
        puts 'Sem problemas encontrados.'
      else
        puts 'Problemas:'
        issues.each { |n, k, errs| puts " - #{n} [#{k}]: #{Array(errs).join('; ')}" }
      end

      puts 'Concluído.'
    end
  end

  desc 'Cria um Druida e evolui até o nível 20 (ou MAX_LEVEL) validando requisitos por nível.'
  task druid20: :environment do
    max_level = (ENV['MAX_LEVEL'] || 20).to_i
    max_level = 20 if max_level > 20
    puts "== Smoke: Druida até o nível #{max_level} =="

    user = User.first || User.create!(name: 'Smoke Tester', username: 'smoke', email: 'smoke@example.com', password: 'secret', password_confirmation: 'secret')

    druid = Klass.find_by!(api_index: 'druid')
    race  = Race.order('RANDOM()').first || Race.first
    sub_r = SubRace.where(race_id: race&.id).order('RANDOM()').first

    char = Character.create!(name: "Smoke-Druid-L#{max_level}", background: 'Smoke test', user_id: user.id, group_id: nil)
    sheet = CharacterCreationService.call(character_id: char.id, race_id: race.id, sub_race_id: sub_r&.id, klass_id: druid.id, abilities: RandomCharacterGenerator.rand_abilities).result

    # Background (quando disponível)
    begin
      BackgroundAssignmentService.call(sheet: sheet, key: %w[acolyte criminal soldier].sample)
    rescue NameError
    end

    # Picks iniciais
    RandomCharacterGenerator.pick_level1_basics!(sheet, druid)
    RandomCharacterGenerator.pick_required_for_level!(sheet, druid, 1)

    # Druid é caster preparado: não precisa de spells_known, mas concedemos cantrips iniciais se houver
    RandomCharacterGenerator.assign_initial_spells!(sheet, druid)

    # Level up até max_level
    (2..max_level).each do |lvl|
      RandomCharacterGenerator.pick_required_for_level!(sheet, druid, lvl)
      LevelUpService.call(sheet_id: sheet.id, klass_id: druid.id, levels: 1)
    end

    # Validação final com guard
    guard = LevelUpGuardService.call(sheet: sheet, klass: druid)
    if guard.success?
      puts "OK: Druida chegou ao nível #{sheet.sheet_klasses.find_by(klass_id: druid.id)&.level}"
    else
      puts "FALHOU validação: #{guard.errors.full_messages.join('; ')}"
    end
  end

  desc 'Simula a criação de N personagens via fluxo equivalente ao formulário (COUNT=10, MAX_LEVEL=1..20)'
  task simulate_form: :environment do
    count = (ENV['COUNT'] || 10).to_i
    max_level = (ENV['MAX_LEVEL'] || 1).to_i
    max_level = [[max_level, 1].max, 20].min
    puts "== Simulação de formulário: #{count} personagens até nível #{max_level} =="

    user = User.first || User.create!(name: 'Smoke Tester', username: 'smoke', email: 'smoke@example.com', password: 'secret', password_confirmation: 'secret')
    raise 'Seeds insuficientes: faltam users/races/klasses.' if Race.count.zero? || Klass.count.zero?

    created = RandomCharacterGenerator.generate_random_characters(count: count, max_level_per_char: max_level, user: user)

    # Validação rápida semelhante ao fluxo do formulário (guard e requisitos)
    issues = []
    created.each do |char|
      sheet = Sheet.find_by(character_id: char.id)
      next unless sheet
      sheet.reload
      sheet.sheet_klasses.each do |sk|
        klass = sk.klass
        guard = LevelUpGuardService.call(sheet: sheet, klass: klass)
        issues << [char.name, klass.name, guard.errors.full_messages] unless guard.success?
      end
      bg = (sheet.metadata || {})['background_summary']
      issues << [char.name, 'Background', ['Background não associado']] if bg.blank? && sheet.background_id.blank?
    end

    if issues.empty?
      puts 'Sem problemas encontrados.'
    else
      puts 'Problemas:'
      issues.each { |n, k, errs| puts " - #{n} [#{k}]: #{Array(errs).join('; ')}" }
    end

    puts 'Concluído.'
  end
end
