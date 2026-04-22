# frozen_string_literal: true

module Modifiers
  module Producers
    # BaseProducer — contrato comum para todos os producers de Modifier.
    #
    # Cada subclasse deve implementar:
    #   #produce → Array<Modifier>
    #
    # Convenções:
    # - Producers são puros: NÃO devem persistir nada nem mutar a sheet.
    # - Recebem `sheet` (ActiveRecord) + um contexto opcional (ex: equipped items).
    # - Devolvem [] se não há contribuição (não levantam exception).
    # - Erros são logados via Rails.logger.warn e o producer skipa graciosamente.
    class BaseProducer
      attr_reader :sheet, :context

      def initialize(sheet, context: {})
        @sheet = sheet
        @context = context || {}
      end

      def produce
        raise NotImplementedError, "#{self.class.name} deve implementar #produce"
      end

      protected

      # Helper para criar um Modifier preservando defaults sensatos do producer.
      def mod(target:, op:, value:, source:, **opts)
        Modifiers::Modifier.new(
          target: target,
          op: op,
          value: value,
          source: source,
          source_kind: source_kind,
          **opts,
        )
      end

      # Subclasses devem sobrescrever para informar a fonte canônica.
      def source_kind
        raise NotImplementedError, "#{self.class.name} deve implementar #source_kind"
      end
    end
  end
end
