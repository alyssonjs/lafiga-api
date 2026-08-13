module ApplicationCable
  class Channel < ActionCable::Channel::Base
    private

    def trace_realtime(stage:, domain:, outcome:, aggregate_type: nil, aggregate_id: nil, error_class: nil)
      Realtime::Telemetry.emit(
        stage: stage,
        domain: domain,
        channel: self.class.name,
        connection_id: realtime_connection_id,
        client_id: realtime_client_id,
        aggregate_type: aggregate_type,
        aggregate_id: aggregate_id,
        actor_id: defined?(@current_user) ? @current_user&.id : nil,
        outcome: outcome,
        error_class: error_class,
      )
    end

    def realtime_client_id
      from_subscription = Realtime::Telemetry.identifier(params[:client_id])
      from_connection = connection.client_id if connection.respond_to?(:client_id)
      from_subscription || Realtime::Telemetry.identifier(from_connection)
    end

    def realtime_connection_id
      value = connection.connection_id if connection.respond_to?(:connection_id)
      Realtime::Telemetry.identifier(value)
    end
  end
end
