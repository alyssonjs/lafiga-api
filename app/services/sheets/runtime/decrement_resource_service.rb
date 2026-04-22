# frozen_string_literal: true

module Sheets
  module Runtime
    # Decrementa (gasta) um recurso de classe — atalho para PATCH de
    # `class_resources_used`. Mantem o contrato canonico de
    # SheetRuntimeState#apply_patch! (merge), evitando que o frontend tenha
    # que ler-modificar-escrever.
    #
    # Exemplo:
    #   DecrementResourceService.call(sheet, key: 'rage', delta: 1)
    #     => incrementa rage em 1 (ja foi usado mais 1)
    #
    #   DecrementResourceService.call(sheet, key: 'ki', delta: 2)
    #     => +2 em ki "usado"
    #
    # Observacoes:
    #   - delta < 0 eh interpretado como recuperar (ex.: Bardo recupera
    #     bardic_inspiration via item magico). O resultado eh clampeado em 0.
    #   - Aceita keys fora do catalogo (logs warning) — frontend pode evoluir
    #     primeiro.
    class DecrementResourceService
      def self.call(sheet, key:, delta: 1)
        new(sheet, key: key, delta: delta).call
      end

      def initialize(sheet, key:, delta: 1)
        @sheet = sheet
        @key   = key.to_s
        @delta = delta.to_i
      end

      def call
        runtime = @sheet.runtime!
        used = Hash(runtime.class_resources_used).dup
        current = used[@key].to_i
        new_value = [current + @delta, 0].max

        if new_value.zero?
          used.delete(@key)
        else
          used[@key] = new_value
        end

        unless Sheets::Runtime::ResourceCatalog.known?(@key)
          Rails.logger.warn(
            "DecrementResourceService: key '#{@key}' nao esta em config/class_resources.yml; " \
              "considere adicionar para que rest services lidem com ele."
          )
        end

        runtime.update!(class_resources_used: used)
        runtime
      end
    end
  end
end
