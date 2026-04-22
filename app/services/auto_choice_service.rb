class AutoChoiceService
  prepend SimpleCommand

  # Serviço para fazer escolhas automáticas quando necessário
  # Ex.: expertise skills para Ladino, fighting styles para Guerreiro, etc.
  
  def initialize(sheet:, klass:, level:)
    @sheet = sheet
    @klass = klass
    @level = level
  end

  def call
    Rails.logger.info "AutoChoiceService: processando escolhas para #{@klass.name} nível #{@level}"
    
    meta = @sheet.metadata || {}
    class_choices = meta['class_choices'] || {}
    per_level = class_choices['per_level'] || {}
    
    # Obter regras da classe
    rule = ClassRules.find(@klass.api_index)
    return true unless rule
    
    required_choices = rule[:required_choices_at_level] || {}
    level_choices = required_choices[@level.to_s] || required_choices[@level]
    
    return true unless level_choices.present?
    
    Rails.logger.info "Escolhas obrigatórias no nível #{@level}: #{level_choices.keys}"
    strict = LevelUpGuardService.strict_required_choices?

    level_choices.each do |choice_key, config|
      # Kit 1.fix-autochoice: warn sempre + skip preenchimento em strict.
      already_set = (per_level.dig(@level.to_s, choice_key.to_s) ||
                     per_level.dig(@level, choice_key.to_s) ||
                     class_choices[choice_key.to_s])
      if already_set.blank?
        Rails.logger.warn(
          "[autochoice-service] would-have-filled key=#{choice_key} klass=#{@klass.api_index} level=#{@level} strict=#{strict}"
        )
      end
      next if strict && already_set.blank?

      make_auto_choice(choice_key, config, class_choices, per_level)
    end

    @sheet.update!(metadata: meta)
    
    Rails.logger.info "AutoChoiceService: escolhas processadas com sucesso"
    true
  rescue StandardError => e
    Rails.logger.error "AutoChoiceService failed: #{e.message}"
    errors.add(:base, e.message)
    false
  end

  private

  def make_auto_choice(choice_key, config, class_choices, per_level)
    choose_count = config[:choose].to_i
    options = config[:options]
    
    Rails.logger.info "Processando escolha: #{choice_key} (escolher #{choose_count} de #{options})"
    
    case choice_key.to_s
    when 'expertise_skills'
      make_expertise_skills_choice(choose_count, class_choices, per_level)
    when 'fighting_style'
      make_fighting_style_choice(options, class_choices)
    when 'metamagic'
      make_metamagic_choice(choose_count, options, class_choices)
    when 'invocations'
      make_invocations_choice(choose_count, options, class_choices)
    when 'pact_boon'
      make_pact_boon_choice(options, class_choices)
    else
      Rails.logger.warn "Escolha não implementada: #{choice_key}"
    end
  end

  def make_expertise_skills_choice(choose_count, class_choices, per_level)
    # Para Ladino: escolher 2 perícias para expertise
    # Respeitar escolhas já gravadas pelo wizard em per_level[@level].expertise_skills:
    # se o usuário já escolheu, não sobrescrever (nem em root nem em per_level).
    level_key = @level.to_s
    per_level_row = per_level[level_key] || per_level[@level] || {}
    existing_per_level = Array(per_level_row['expertise_skills'] || per_level_row[:expertise_skills])

    if existing_per_level.size >= choose_count
      Rails.logger.info "Expertise skills já presentes em per_level[#{level_key}], mantendo: #{existing_per_level.first(choose_count).join(', ')}"
      return
    end

    # Pool de perícias proficientes disponíveis: preferir per_level['1'].skills (canónico)
    # antes de cair para o legado em class_choices.skills_selected.
    pl1_skills = (per_level['1'] || per_level[1] || {})
    pl1_skills = Array(pl1_skills['skills'] || pl1_skills[:skills])
    available_skills = pl1_skills.presence || Array(class_choices['skills_selected'])
    available_skills = available_skills.map { |x| x.is_a?(Hash) ? (x['name'] || x[:name]) : x }.compact

    chosen = if available_skills.length >= choose_count
               available_skills.first(choose_count)
             else
               # Se não há perícias suficientes, escolher perícias padrão
               default_skills = ['Furtividade', 'Percepção']
               default_skills.first(choose_count)
             end

    # Escrever canónico em per_level[@level].expertise_skills.
    per_level[level_key] ||= {}
    per_level[level_key]['expertise_skills'] = chosen
    class_choices['per_level'] = per_level

    # Manter root vazio para evitar discrepância — só preencher se não havia per_level e
    # nada em root (compat extrema com leitores antigos).
    class_choices['expertise_skills'] = chosen if class_choices['expertise_skills'].blank?

    Rails.logger.info "Expertise skills escolhidas (per_level[#{level_key}]): #{chosen.join(', ')}"
  end

  def make_fighting_style_choice(options, class_choices)
    # Escolher um estilo de luta
    if options.is_a?(Array) && options.any?
      chosen = options.first
      class_choices['fighting_style'] = chosen
      Rails.logger.info "Fighting style escolhido: #{chosen}"
    else
      # Estilos padrão por classe
      default_styles = {
        'fighter' => 'Duelo',
        'paladin' => 'Proteção',
        'ranger' => 'Arco'
      }
      chosen = default_styles[@klass.api_index] || 'Duelo'
      class_choices['fighting_style'] = chosen
      Rails.logger.info "Fighting style padrão escolhido: #{chosen}"
    end
  end

  def make_metamagic_choice(choose_count, options, class_choices)
    # Kit 1.PoC: options pode vir como Symbol :metamagic → resolve via catálogo canônico.
    resolved = if options.is_a?(Symbol)
                 begin
                   ClassChoicesCatalog.canonical_names(options)
                 rescue StandardError => e
                   Rails.logger.warn "AutoChoiceService.make_metamagic_choice: falhou ao resolver :#{options}: #{e.message}"
                   []
                 end
               elsif options.is_a?(Array)
                 options
               else
                 []
               end

    if resolved.any? && resolved.length >= choose_count
      chosen = resolved.first(choose_count)
    else
      chosen = (resolved.presence || ['Magia Acelerada', 'Magia Expandida']).first(choose_count)
    end
    class_choices['metamagic'] = chosen
    Rails.logger.info "Metamagic escolhidas: #{chosen.join(', ')}"
  end

  def make_invocations_choice(choose_count, options, class_choices)
    # Kit 1.invocations: resolve via catálogo canônico (eldritch_invocations.yml).
    # Filtra entries sem prereqs (level/pact/spell) para auto-fill seguro em nv 2.
    resolved = if options.is_a?(Symbol)
                 begin
                   safe = ClassChoicesCatalog.load(options).reject do |e|
                     pr = e[:prereqs] || {}
                     pr['level'].to_i > 2 || pr['pact'].present? || pr['spell'].present? || pr['blast']
                   end
                   safe.map { |e| e[:slug] }
                 rescue StandardError => e
                   Rails.logger.warn "AutoChoiceService.make_invocations_choice: falhou ao resolver :#{options}: #{e.message}"
                   []
                 end
               elsif options.is_a?(Array)
                 options
               else
                 []
               end

      chosen = if resolved.any? && resolved.length >= choose_count
                 resolved.first(choose_count)
               else
                 (resolved.presence || %w[ei-devils-sight ei-armor-of-shadows]).first(choose_count)
               end
      class_choices['invocations'] = chosen
      Rails.logger.info "Invocations escolhidas: #{chosen.join(', ')}"
  end

  def make_pact_boon_choice(options, class_choices)
    # Para Bruxo: escolher pacto
    if options.is_a?(Array) && options.any?
      chosen = options.first
      class_choices['pact_boon'] = chosen
      Rails.logger.info "Pact boon escolhido: #{chosen}"
    else
      # Pacto padrão
      class_choices['pact_boon'] = 'Pacto do Tomo'
      Rails.logger.info "Pact boon padrão escolhido: Pacto do Tomo"
    end
  end
end
