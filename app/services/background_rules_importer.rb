# frozen_string_literal: true

# Sincroniza registros `Background` a partir de `BackgroundRules::RULES` + tabelas de
# personalidade em `config/backgrounds_phb.yml`, para popular `rules` JSONB.
class BackgroundRulesImporter
  class << self
    def sync_from_code_and_yaml!
      yaml = load_phb_yaml
      Background.transaction do
        BackgroundRules::RULES.each do |_sym, rule|
          slug = (rule[:id] || rule['id']).to_s
          upsert_root!(slug, rule, yaml)
        end
      end
      BackgroundRules.clear_cache!
    end

    private

    def load_phb_yaml
      path = Rails.root.join('config', 'backgrounds_phb.yml')
      return {} unless File.exist?(path)

      YAML.load_file(path) || {}
    rescue StandardError => e
      Rails.logger.warn("BackgroundRulesImporter: não leu YAML (#{e.message})")
      {}
    end

    def upsert_root!(slug, rule, yaml_root)
      yb = yaml_root['backgrounds']&.[](slug)
      rules_hash = rule.deep_dup
      merge_personality_from_yaml!(rules_hash, yb)

      bg = Background.find_or_initialize_by(api_index: slug)
      bg.name = rules_hash[:name].to_s
      feat = rules_hash[:feature] || {}
      bg.feature_name = feat[:name].to_s if feat[:name].present?
      bg.feature_desc = feat[:desc].to_s if feat[:desc].present?
      bg.rules = stringify_keys_deep(rules_hash)
      bg.published = true
      bg.parent_api_index = nil
      bg.save!
    end

    def merge_personality_from_yaml!(rules_hash, yb)
      return if yb.blank?

      %w[personality_traits ideals bonds flaws].each do |k|
        next if yb[k].blank?

        rules_hash[k.to_sym] = yb[k]
      end
    end

    def stringify_keys_deep(obj)
      case obj
      when Hash
        obj.each_with_object({}) { |(k, v), h| h[k.to_s] = stringify_keys_deep(v) }
      when Array
        obj.map { |e| stringify_keys_deep(e) }
      else
        obj
      end
    end
  end
end
