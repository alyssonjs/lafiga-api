require 'yaml'

module Sheets
  module Runtime
    # Catalogo de recursos de classe (Fase C). Carrega config/class_resources.yml
    # uma unica vez (memo) e expoe lookup por chave + helpers para identificar
    # quais recursos zeram em short/long rest.
    class ResourceCatalog
      CONFIG_PATH = Rails.root.join('config', 'class_resources.yml').freeze

      class << self
        def all
          @all ||= load_yaml.freeze
        end

        # Recursos que zeram em descanso curto, considerando overrides
        # `recharge_at_level` quando `level` for fornecido (P2.14).
        # Exemplo: bardic_inspiration tem `recharge: long` mas `recharge_at_level: { 5: short }`,
        # entao `short_rest_keys(level: 5)` inclui bardic_inspiration; `short_rest_keys`
        # (sem nivel) usa apenas o `recharge` base.
        def short_rest_keys(level: nil)
          all.select { |key, _| recharge_for(key, level: level) == 'short' }.keys
        end

        # Recursos que zeram em descanso longo (TUDO — regra D&D: tudo que
        # recupera em curto tambem recupera em longo).
        def long_rest_keys
          all.keys
        end

        # Recarga efetiva para uma chave + nivel (opcional).
        # Sem nivel ou sem overrides, retorna `recharge` base.
        # Com nivel, aplica o maior `recharge_at_level` cujo trigger <= nivel.
        def recharge_for(key, level: nil)
          entry = all[key.to_s]
          return nil unless entry
          base = entry['recharge'].to_s
          return base if level.nil?

          overrides = entry['recharge_at_level']
          return base unless overrides.is_a?(Hash)

          applicable = overrides
                       .select { |k, _| k.to_i <= level.to_i }
                       .max_by { |k, _| k.to_i }
          return base unless applicable
          applicable[1].to_s
        end

        def known?(key)
          all.key?(key.to_s)
        end

        def reload!
          @all = nil
        end

        private

        def load_yaml
          raw = YAML.load_file(CONFIG_PATH)
          raw.is_a?(Hash) ? raw : {}
        end
      end
    end
  end
end
