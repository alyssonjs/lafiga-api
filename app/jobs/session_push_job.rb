# frozen_string_literal: true

# Dispara as notificações Web Push de EVENTO de sessão (criada / cancelada) FORA
# do request HTTP — o Push::Sender é síncrono/bloqueante (uma chamada de rede por
# assinatura) e o box de prod é modesto. Recebe ids (boa prática do ActiveJob),
# recarrega a sessão e delega ao Push::SessionNotifier.
class SessionPushJob < ApplicationJob
  queue_as :default

  # @param schedule_id [Integer]
  # @param event [String] 'created' | 'cancelled'
  # @param actor_id [Integer, nil] quem disparou a ação (não recebe, salvo o Mestre)
  def perform(schedule_id, event, actor_id = nil)
    schedule = Schedule.includes(:group, :date_dimension, characters: :user).find_by(id: schedule_id)
    return if schedule.nil?

    Push::SessionNotifier.call(schedule: schedule, event: event, actor_id: actor_id)
  end
end
