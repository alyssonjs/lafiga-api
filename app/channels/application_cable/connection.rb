module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :connection_id, :client_id

    def connect
      self.connection_id = Realtime::Telemetry.identifier(request.params[:connection_id]) || SecureRandom.uuid
      self.client_id = Realtime::Telemetry.identifier(request.params[:client_id])
      Realtime::Telemetry.emit(
        stage: 'connection_opened',
        domain: 'cable',
        connection_id: connection_id,
        client_id: client_id,
        outcome: 'succeeded',
      )
    end

    def disconnect
      Realtime::Telemetry.emit(
        stage: 'connection_closed',
        domain: 'cable',
        connection_id: connection_id,
        client_id: client_id,
        outcome: 'succeeded',
      )
    end
  end
end
