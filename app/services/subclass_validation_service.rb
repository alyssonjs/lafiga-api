# frozen_string_literal: true

class SubclassValidationService
  prepend SimpleCommand

  # Validações específicas para subclasses baseadas em suas regras
  def initialize(sheet_klass, subclass_id, level)
    @sheet_klass = sheet_klass
    @subclass_id = subclass_id
    @level = level
    @klass = @sheet_klass.klass
  end

  def call
    return true unless @subclass_id.present?

    subclass_rule = SubclassRules.find(@klass.api_index, @subclass_id)
    return true unless subclass_rule

    validate_subclass_requirements(subclass_rule)
    validate_spellcasting_requirements(subclass_rule)
    validate_feature_requirements(subclass_rule)

    errors.empty?
  end

  private

  def validate_subclass_requirements(subclass_rule)
    case @klass.api_index
    when 'barbarian'
      validate_barbarian_subclass(subclass_rule)
    when 'bard'
      validate_bard_subclass(subclass_rule)
    when 'warlock'
      validate_warlock_subclass(subclass_rule)
    when 'cleric'
      validate_cleric_subclass(subclass_rule)
    when 'druid'
      validate_druid_subclass(subclass_rule)
    when 'sorcerer'
      validate_sorcerer_subclass(subclass_rule)
    when 'fighter'
      validate_fighter_subclass(subclass_rule)
    when 'rogue'
      validate_rogue_subclass(subclass_rule)
    when 'wizard'
      validate_wizard_subclass(subclass_rule)
    when 'monk'
      validate_monk_subclass(subclass_rule)
    when 'paladin'
      validate_paladin_subclass(subclass_rule)
    when 'ranger'
      validate_ranger_subclass(subclass_rule)
    end
  end

  def validate_barbarian_subclass(subclass_rule)
    case @subclass_id
    when 'cicatrizes_runicas'
      # Bárbaro das Cicatrizes Rúnicas precisa de Carisma para spellcasting
      if @level >= 3 && @sheet_klass.sheet.cha < 13
        errors.add(:base, 'Bárbaro das Cicatrizes Rúnicas requer Carisma 13+ para usar magia')
      end
    when 'desistente'
      # Desistente não pode usar itens mágicos
      if @sheet_klass.sheet.sheet_items.joins(:item).where(items: { magical: true }).exists?
        errors.add(:base, 'Desistente não pode usar itens mágicos')
      end
    when 'furioso_imortal'
      # Furioso Imortal precisa de Constituição alta para sobreviver
      if @sheet_klass.sheet.con < 14
        errors.add(:base, 'Furioso Imortal recomenda Constituição 14+ para máxima eficácia')
      end
    end
  end

  def validate_bard_subclass(subclass_rule)
    case @subclass_id
    when 'busca_da_cancao'
      # Busca da Canção precisa de instrumentos musicais
      if @sheet_klass.sheet.sheet_items.joins(:item).where(items: { category: 'instrument' }).empty?
        errors.add(:base, 'Busca da Canção requer pelo menos um instrumento musical')
      end
    when 'comedia'
      # Comédia precisa de Carisma alto
      if @sheet_klass.sheet.cha < 15
        errors.add(:base, 'Comédia recomenda Carisma 15+ para máxima eficácia')
      end
    when 'pavor'
      # Pavor precisa de Intimidação
      # Esta validação seria mais complexa, dependendo de como as perícias são armazenadas
    end
  end

  def validate_warlock_subclass(subclass_rule)
    case @subclass_id
    when 'a_morte'
      # A Morte precisa de Carisma alto para controlar mortos-vivos
      if @level >= 10 && @sheet_klass.sheet.cha < 16
        errors.add(:base, 'A Morte requer Carisma 16+ para controlar mortos-vivos efetivamente')
      end
    when 'arcanjo_vingador'
      # Arcanjo Vingador precisa de alinhamento não-caótico
      if @sheet_klass.sheet.alignment&.name&.match?(/caótico/i)
        errors.add(:base, 'Arcanjo Vingador não pode ser caótico')
      end
    when 'vazio'
      # O Vazio precisa de Sabedoria para resistir à corrupção
      if @sheet_klass.sheet.wis < 13
        errors.add(:base, 'O Vazio requer Sabedoria 13+ para resistir à corrupção')
      end
    end
  end

  def validate_cleric_subclass(subclass_rule)
    case @subclass_id
    when 'agua'
      # Domínio da Água precisa de Sabedoria alta
      if @sheet_klass.sheet.wis < 15
        errors.add(:base, 'Domínio da Água recomenda Sabedoria 15+ para máxima eficácia')
      end
    when 'tempo'
      # Domínio do Tempo precisa de Inteligência para compreender temporalidade
      if @sheet_klass.sheet.int < 13
        errors.add(:base, 'Domínio do Tempo requer Inteligência 13+ para compreender temporalidade')
      end
    end
  end

  def validate_druid_subclass(subclass_rule)
    case @subclass_id
    when 'infestacao'
      # Círculo da Infestação precisa de Constituição para resistir a doenças
      if @sheet_klass.sheet.con < 14
        errors.add(:base, 'Círculo da Infestação recomenda Constituição 14+ para resistir a doenças')
      end
    when 'mundos'
      # Círculo dos Mundos precisa de Inteligência para compreender múltiplos planos
      if @sheet_klass.sheet.int < 14
        errors.add(:base, 'Círculo dos Mundos requer Inteligência 14+ para compreender múltiplos planos')
      end
    end
  end

  def validate_sorcerer_subclass(subclass_rule)
    case @subclass_id
    when 'feiticaria_sangue'
      # Feitiçaria do Sangue precisa de Constituição para usar sangue
      if @sheet_klass.sheet.con < 14
        errors.add(:base, 'Feitiçaria do Sangue recomenda Constituição 14+ para usar sangue efetivamente')
      end
    when 'origem_aberrante'
      # Origem Aberrante precisa de Sabedoria para resistir à loucura
      if @sheet_klass.sheet.wis < 13
        errors.add(:base, 'Origem Aberrante requer Sabedoria 13+ para resistir à loucura')
      end
    end
  end

  def validate_fighter_subclass(subclass_rule)
    case @subclass_id
    when 'atirador_inigualavel'
      # Atirador Inigualável precisa de Destreza alta
      if @sheet_klass.sheet.dex < 15
        errors.add(:base, 'Atirador Inigualável recomenda Destreza 15+ para máxima precisão')
      end
    when 'kensai'
      # Kensai precisa de uma arma específica escolhida
      # Esta validação seria mais complexa, dependendo de como as escolhas são armazenadas
    end
  end

  def validate_rogue_subclass(subclass_rule)
    case @subclass_id
    when 'dancarino_sombras'
      # Dançarino das Sombras precisa de Destreza e Carisma
      if @sheet_klass.sheet.dex < 14 || @sheet_klass.sheet.cha < 13
        errors.add(:base, 'Dançarino das Sombras requer Destreza 14+ e Carisma 13+')
      end
    when 'larapio_almas'
      # Larápio de Almas precisa de Carisma para controlar almas
      if @sheet_klass.sheet.cha < 15
        errors.add(:base, 'Larápio de Almas requer Carisma 15+ para controlar almas efetivamente')
      end
    end
  end

  def validate_wizard_subclass(subclass_rule)
    case @subclass_id
    when 'iniciacao_demonologia'
      # Iniciação em Demonologia precisa de Carisma para controlar demônios
      if @sheet_klass.sheet.cha < 14
        errors.add(:base, 'Iniciação em Demonologia requer Carisma 14+ para controlar demônios')
      end
    when 'maestria_alquimica'
      # Maestria Alquímica precisa de Inteligência alta
      if @sheet_klass.sheet.int < 16
        errors.add(:base, 'Maestria Alquímica recomenda Inteligência 16+ para máxima eficácia')
      end
    end
  end

  def validate_monk_subclass(subclass_rule)
    case @subclass_id
    when 'caminho_aco'
      # Caminho do Aço precisa de Força para usar armas pesadas
      if @sheet_klass.sheet.str < 13
        errors.add(:base, 'Caminho do Aço requer Força 13+ para usar armas pesadas')
      end
    when 'caminho_mestre_bebado'
      # Mestre Bêbado precisa de Constituição para resistir aos efeitos do álcool
      if @sheet_klass.sheet.con < 14
        errors.add(:base, 'Mestre Bêbado recomenda Constituição 14+ para resistir aos efeitos do álcool')
      end
    end
  end

  def validate_paladin_subclass(subclass_rule)
    case @subclass_id
    when 'juramento_danacao'
      # Juramento de Danação precisa de alinhamento maligno
      if @sheet_klass.sheet.alignment&.name&.match?(/bom|leal/i)
        errors.add(:base, 'Juramento de Danação não pode ser bom ou leal')
      end
    when 'juramento_equilibrio'
      # Juramento de Equilíbrio precisa de alinhamento neutro
      unless @sheet_klass.sheet.alignment&.name&.match?(/neutro/i)
        errors.add(:base, 'Juramento de Equilíbrio deve ser neutro')
      end
    end
  end

  def validate_ranger_subclass(subclass_rule)
    case @subclass_id
    when 'arqueiro_floresta_alta'
      # Arqueiro da Floresta Alta precisa de Destreza alta
      if @sheet_klass.sheet.dex < 15
        errors.add(:base, 'Arqueiro da Floresta Alta recomenda Destreza 15+ para máxima precisão')
      end
    when 'mestre_bestas'
      # Mestre das Bestas precisa de Sabedoria para se comunicar com animais
      if @sheet_klass.sheet.wis < 14
        errors.add(:base, 'Mestre das Bestas requer Sabedoria 14+ para se comunicar com animais')
      end
    end
  end

  def validate_spellcasting_requirements(subclass_rule)
    return unless subclass_rule[:spellcasting]

    case @klass.api_index
    when 'barbarian'
      # Bárbaro das Cicatrizes Rúnicas usa Carisma para spellcasting
      if @subclass_id == 'cicatrizes_runicas' && @sheet_klass.sheet.cha < 13
        errors.add(:base, 'Bárbaro das Cicatrizes Rúnicas requer Carisma 13+ para conjuração')
      end
    end
  end

  def validate_feature_requirements(subclass_rule)
    # Validações gerais de features
    features = subclass_rule[:features] || {}
    
    features.each do |level, level_features|
      next unless level.to_i <= @level
      
      level_features.each do |feature_name, feature_description|
        # Validações específicas por feature podem ser adicionadas aqui
        case feature_name
        when /spellcasting|conjuração/i
          validate_spellcasting_feature(feature_name, feature_description)
        when /transformação|avatar/i
          validate_transformation_feature(feature_name, feature_description)
        end
      end
    end
  end

  def validate_spellcasting_feature(feature_name, feature_description)
    # Validações específicas para features de spellcasting
    case @klass.api_index
    when 'barbarian'
      if @sheet_klass.sheet.cha < 13
        errors.add(:base, "#{feature_name} requer Carisma 13+ para conjuração")
      end
    end
  end

  def validate_transformation_feature(feature_name, feature_description)
    # Validações específicas para features de transformação
    case @klass.api_index
    when 'druid'
      if @sheet_klass.sheet.wis < 13
        errors.add(:base, "#{feature_name} requer Sabedoria 13+ para transformação")
      end
    end
  end
end
