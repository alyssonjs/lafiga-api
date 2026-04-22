# frozen_string_literal: true

require 'yaml'

namespace :classes do
  desc 'Aplica overrides de classes a partir de config/class_overrides.yml (ClassLevels e Features)'
  task apply_overrides: :environment do
    path = Rails.root.join('config','class_overrides.yml')
    unless File.exist?(path)
      puts "[classes] Arquivo não encontrado: #{path}"
      next
    end

    data = YAML.load_file(path) || {}
    data.each do |klass_key, payload|
      k_api = (payload['id'] || klass_key).to_s
      klass = Klass.find_by(api_index: k_api)
      if klass.nil?
        puts "[classes] Classe não encontrada (api_index=#{k_api}); pulando"
        next
      end

      puts "[classes] Importando overrides para #{klass.name} (#{k_api})"

      # Derivar níveis de ASI a partir do YAML (categoria ability_score_improvement)
      asi_levels_yaml = Array(payload['levels']).select { |r|
        Array(r['features']).any? { |f| f.is_a?(Hash) && f['category'].to_s == 'ability_score_improvement' }
      }.map { |r| r['level'].to_i }.uniq

      # Fallback: usar ClassRules se YAML não listar explicitamente
      if asi_levels_yaml.empty?
        begin
          rule = ClassRules.find(k_api)
          arr = rule&.dig(:feature_rules, :ability_score_improvement, :levels)
          asi_levels_yaml = Array(arr).map(&:to_i).uniq
        rescue => _e
          asi_levels_yaml = []
        end
      end

      # Garantir níveis 1..20 com proficiência e ASI cumulativo
      cumulative = 0
      (1..20).each do |lvl|
        prof = 2 + ((lvl - 1) / 4)
        cumulative += 1 if asi_levels_yaml.include?(lvl)
        cl = klass.class_levels.find_or_initialize_by(level: lvl)
        cl.prof_bonus = prof
        cl.ability_score_bonuses = cumulative
        cl.save!
      end

      Array(payload['levels']).each do |row|
        lvl = row['level'].to_i
        next if lvl <= 0
        cl = klass.class_levels.find_or_create_by!(level: lvl) do |rec|
          rec.prof_bonus = 2 + ((lvl - 1) / 4)
          rec.ability_score_bonuses = 0
        end

        Array(row['features']).each do |feat|
          api_index = (feat['api_index'] || feat['name'].to_s.parameterize(separator: '_')).to_s
          name      = feat['name'] || api_index.titleize
          desc      = feat['description']
          raw_cat   = feat['category'].to_s

          # Mapear categoria para enum conhecido (fallback: class_feature)
          cat = %w[class_feature subclass_feature racial_trait feat].include?(raw_cat) ? raw_cat : 'class_feature'

          f = Feature.find_or_initialize_by(api_index: api_index)
          f.name = name
          f.description = desc if desc.present?
          f.category = cat
          f.save!

          cl.features << f unless cl.features.include?(f)
        end
      end
    end

    puts "[classes] Concluído."
  end
end
