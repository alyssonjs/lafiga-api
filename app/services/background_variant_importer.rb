# frozen_string_literal: true

# Carrega variantes de antecedente a partir de `config/background_variants_phb.yml`
# (ou outro path). Cada variante é um `Background` com `parent_api_index` e `rules`
# parciais que fazem deep_merge sobre o pai em `BackgroundRules.build_merged_hash`.
class BackgroundVariantImporter
  class << self
    def import_from_yaml!(path = Rails.root.join('config', 'background_variants_phb.yml'))
      return unless File.exist?(path)

      data = YAML.load_file(path) || {}
      variants = data['variants'] || {}
      Background.transaction do
        variants.each do |slug, cfg|
          next unless cfg.is_a?(Hash)

          parent = cfg['parent_api_index'].to_s
          name = (cfg['name'] || slug).to_s
          rules = cfg['rules'].is_a?(Hash) ? cfg['rules'].deep_stringify_keys : {}
          published = cfg.key?('published') ? ActiveModel::Type::Boolean.new.cast(cfg['published']) : true

          bg = Background.find_or_initialize_by(api_index: slug.to_s)
          bg.parent_api_index = parent.presence
          bg.name = name
          bg.rules = rules
          bg.published = published
          feat = rules['feature']
          if feat.is_a?(Hash)
            bg.feature_name = feat['name'].to_s if feat['name'].present?
            bg.feature_desc = feat['desc'].to_s if feat['desc'].present?
          end
          bg.save!
        end
      end
      BackgroundRules.clear_cache!
    end
  end
end
