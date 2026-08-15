# frozen_string_literal: true

# Assinatura de Web Push de UM device do usuário (endpoint do push service + chaves
# públicas do browser). Um usuário pode ter várias (celular, desktop…). Enviada por
# Push::Sender; endpoints mortos (404/410) são removidos na entrega.
class PushSubscription < ApplicationRecord
  belongs_to :user

  validates :endpoint, presence: true, uniqueness: true
  validates :p256dh_key, presence: true
  validates :auth_key, presence: true
end
