# frozen_string_literal: true

module Realtime
  class Telemetry
    IDENTIFIER_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._:-]{0,127}\z/.freeze

    STAGES = %w[
      command_created command_sent command_received command_validated command_persisted
      command_acknowledged command_rejected command_failed
      subscription_created subscription_confirmed subscription_rejected
      subscription_removed connection_opened connection_closed
      event_broadcast event_received event_applied event_ignored reconciled
    ].freeze
    DOMAINS = %w[cable map combat feed inventory session].freeze
    OUTCOMES = %w[pending accepted rejected succeeded failed ignored duplicate].freeze

    IDENTIFIER_FIELDS = %i[
      command_id event_id client_id connection_id event_type aggregate_type
      aggregate_id actor_id channel outcome error_class
    ].freeze
    NUMERIC_FIELDS = %i[duration_ms base_version result_version sequence].freeze

    class << self
      def emit(**attributes)
        entry = {
          kind: 'realtime_trace',
          at: Time.current.utc.iso8601(6),
        }

        stage = enum_value(attributes[:stage], STAGES)
        domain = enum_value(attributes[:domain], DOMAINS)
        entry[:stage] = stage if stage
        entry[:domain] = domain if domain

        IDENTIFIER_FIELDS.each do |field|
          value = field == :outcome ? enum_value(attributes[field], OUTCOMES) : identifier(attributes[field])
          entry[field] = value if value
        end

        NUMERIC_FIELDS.each do |field|
          value = finite_number(attributes[field])
          entry[field] = value if value
        end

        Rails.logger.info(entry.to_json)
        entry
      end

      def identifier(value)
        candidate = value.to_s
        return nil if candidate.blank? || !IDENTIFIER_PATTERN.match?(candidate)

        candidate
      end

      def request_context(request)
        {
          client_id: identifier(request.headers['X-Lafiga-Client-Id']),
          command_id: identifier(request.headers['X-Lafiga-Command-Id']),
        }
      end

      private

      def enum_value(value, allowed)
        candidate = value.to_s
        allowed.include?(candidate) ? candidate : nil
      end

      def finite_number(value)
        return nil unless value.is_a?(Numeric) && value.finite?

        value
      end
    end
  end
end
