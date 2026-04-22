# frozen_string_literal: true

namespace :subclasses do
  desc "Import new subclasses from subclass rules"
  task import: :environment do
    puts "Importando novas subclasses..."
    
    subclass_rules = SubclassRules.rules
    
    subclass_rules.each do |class_id, subclasses|
      klass = Klass.find_by(api_index: class_id)
      
      unless klass
        puts "Classe não encontrada: #{class_id}"
        next
      end
      
      puts "Processando classe: #{klass.name}"
      
      subclasses.each do |subclass_id, subclass_data|
        # Verificar se subclasse já existe
        existing = SubKlass.find_by(
          klass: klass,
          api_index: subclass_id
        )
        
        if existing
          puts "  Subclasse já existe: #{subclass_data[:name]}"
          next
        end
        
        # Criar subclasse
        sub_klass = SubKlass.create!(
          klass: klass,
          name: subclass_data[:name],
          api_index: subclass_id,
          description: subclass_data[:description],
          subclass_flavor: extract_flavor(subclass_data[:name])
        )
        
        puts "  Criado: #{subclass_data[:name]}"
        
        # Criar features da subclasse
        create_subclass_features(sub_klass, subclass_data[:features])
        
        # Criar níveis e features por nível
        create_subclass_levels(sub_klass, subclass_data[:features])
        
        # Criar spellcasting se aplicável
        create_subclass_spellcasting(sub_klass, subclass_data[:spellcasting]) if subclass_data[:spellcasting]
      end
    end
    
    puts "Importação concluída!"
  end
  
  desc "List all subclasses by class"
  task list: :environment do
    Klass.includes(:sub_klasses).each do |klass|
      puts "\n#{klass.name}:"
      klass.sub_klasses.each do |sub_klass|
        puts "  - #{sub_klass.name} (#{sub_klass.custom_subclass? ? 'custom' : 'PHB'})"
      end
    end
  end
  
  desc "Validate subclass data"
  task validate: :environment do
    puts "Validando dados das subclasses..."
    
    issues = []
    
    SubKlass.includes(:klass, :sub_klass_levels).each do |sub_klass|
      # Verificar se tem níveis definidos
      if sub_klass.sub_klass_levels.empty?
        issues << "#{sub_klass.name} não tem níveis definidos"
      end
      
      # Verificar se tem features
      if sub_klass.features.empty?
        issues << "#{sub_klass.name} não tem features definidas"
      end
    end
    
    if issues.empty?
      puts "Todas as subclasses estão válidas!"
    else
      puts "Problemas encontrados:"
      issues.each { |issue| puts "  - #{issue}" }
    end
  end
  
  private
  
  def extract_flavor(name)
    # Extrair sabor/tema do nome da subclasse
    case name
    when /Caminho do/
      name.gsub('Caminho do ', '')
    when /Colégio da/
      name.gsub('Colégio da ', '')
    when /Colégio do/
      name.gsub('Colégio do ', '')
    when /Domínio da/
      name.gsub('Domínio da ', '')
    when /Domínio do/
      name.gsub('Domínio do ', '')
    when /Círculo da/
      name.gsub('Círculo da ', '')
    when /Círculo do/
      name.gsub('Círculo do ', '')
    when /Círculo das/
      name.gsub('Círculo das ', '')
    when /Círculo dos/
      name.gsub('Círculo dos ', '')
    when /Juramento de/
      name.gsub('Juramento de ', '')
    when /Tradição/
      name.gsub('Tradição ', '')
    else
      name
    end
  end
  
  def create_subclass_features(sub_klass, features)
    return unless features
    
    features.each do |level, level_features|
      level_features.each do |feature_name, feature_description|
        feature = Feature.find_or_create_by(
          api_index: generate_api_index(feature_name),
          name: feature_name
        ) do |f|
          f.description = feature_description
          f.category = :subclass_feature
        end
        
        # Associar feature ao nível da subclasse
        level_record = sub_klass.sub_klass_levels.find_or_create_by(level: level.to_i)
        level_record.features << feature unless level_record.features.include?(feature)
      end
    end
  end
  
  def create_subclass_levels(sub_klass, features)
    return unless features
    
    # Criar níveis baseados nas features
    levels = features.keys.map(&:to_i).uniq.sort
    
    levels.each do |level_num|
      sub_klass.sub_klass_levels.find_or_create_by(level: level_num)
    end
  end
  
  def create_subclass_spellcasting(sub_klass, spellcasting_data)
    return unless spellcasting_data
    
    puts "    Spellcasting detectado para #{sub_klass.name}"
    puts "    Habilidade: #{spellcasting_data[:ability]}"
    puts "    Lista: #{spellcasting_data[:spell_list]}"
    
    # Criar spellcasting para cada nível da subclasse
    sub_klass.sub_klass_levels.each do |level_record|
      spellcasting = SubclassSpellcastingService.create_spellcasting_record(sub_klass, level_record.level)
      if spellcasting
        puts "      Spellcasting criado para nível #{level_record.level}"
      end
    end
  end
  
  def generate_api_index(name)
    name.downcase
        .gsub(/[^a-z0-9\s]/, '')
        .gsub(/\s+/, '_')
        .strip
  end
end
