# frozen_string_literal: true

# Leitura de config/dnd_translations.yml para textos PT sem reimportar o banco.
module DndTranslations
  class << self
    def reload!
      @data = nil
    end

    def data
      if Rails.env.development?
        load_yaml
      else
        @data ||= load_yaml
      end
    end

    def translated_feature_name(api_index, fallback = nil)
      pick_string(data['features'], api_index, fallback)
    end

    def translated_feature_description(api_index, fallback = nil)
      pick_string(data['feature_descs'], api_index, fallback)
    end

    private

    def load_yaml
      path = Rails.root.join('config', 'dnd_translations.yml')
      return {} unless File.exist?(path)

      raw = YAML.load_file(path)
      raw.is_a?(Hash) ? raw.transform_keys(&:to_s) : {}
    end

    def pick_string(section, api_index, fallback)
      return fallback if section.nil? || !section.is_a?(Hash)

      val = section[api_index.to_s]
      val.is_a?(String) && val.strip.present? ? val : fallback
    end
  end
end
