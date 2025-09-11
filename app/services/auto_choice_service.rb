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
    
    level_choices.each do |choice_key, config|
      make_auto_choice(choice_key, config, class_choices, per_level)
    end
    
    # Atualizar metadata
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
      make_expertise_skills_choice(choose_count, class_choices)
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

  def make_expertise_skills_choice(choose_count, class_choices)
    # Para Ladino: escolher 2 perícias para expertise
    available_skills = class_choices['skills_selected'] || []
    
    if available_skills.length >= choose_count
      # Escolher as primeiras N perícias disponíveis
      chosen = available_skills.first(choose_count)
      class_choices['expertise_skills'] = chosen
      Rails.logger.info "Expertise skills escolhidas: #{chosen.join(', ')}"
    else
      # Se não há perícias suficientes, escolher perícias padrão
      default_skills = ['Furtividade', 'Percepção']
      class_choices['expertise_skills'] = default_skills.first(choose_count)
      Rails.logger.info "Expertise skills padrão escolhidas: #{class_choices['expertise_skills'].join(', ')}"
    end
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
    # Para Feiticeiro: escolher metamágicas
    if options.is_a?(Array) && options.length >= choose_count
      chosen = options.first(choose_count)
      class_choices['metamagic'] = chosen
      Rails.logger.info "Metamagic escolhidas: #{chosen.join(', ')}"
    else
      # Metamágicas padrão
      default_metamagic = ['Acelerar Magia', 'Expandir Magia']
      class_choices['metamagic'] = default_metamagic.first(choose_count)
      Rails.logger.info "Metamagic padrão escolhidas: #{class_choices['metamagic'].join(', ')}"
    end
  end

  def make_invocations_choice(choose_count, options, class_choices)
    # Para Bruxo: escolher invocações
    if options == :invocations_core
      # Invocações básicas disponíveis
      core_invocations = [
        'Visão do Diabo',
        'Maldição de Eldritch',
        'Armadura de Agathys'
      ]
      chosen = core_invocations.first(choose_count)
      class_choices['invocations'] = chosen
      Rails.logger.info "Invocations escolhidas: #{chosen.join(', ')}"
    else
      # Invocações padrão
      default_invocations = ['Visão do Diabo', 'Maldição de Eldritch']
      class_choices['invocations'] = default_invocations.first(choose_count)
      Rails.logger.info "Invocations padrão escolhidas: #{class_choices['invocations'].join(', ')}"
    end
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
