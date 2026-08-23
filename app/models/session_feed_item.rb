# frozen_string_literal: true

# Persistência do feed da sessão (chat + dice rolls) — alimenta o histórico do
# DiceRollBubble entre conexões. Distinto de SessionLog (que é estruturado por
# tipo de log narrativo). Veja CreateSessionFeedItems migration para racional.
#
# Itens são gravados pelo SessionFeedChannel#feed_item antes do broadcast
# ActionCable. Retenção via SessionFeed::Retention.
class SessionFeedItem < ApplicationRecord
  KINDS = %w[chat roll roll_pending attack_hit_resolution].freeze

  # Quem pode LER o item.
  #   all     — chat Geral, todos da mesa (Mestre incluído)
  #   players — chat da EQUIPE: a mesa combina o plano SEM o Mestre
  #   dm      — o caderno do Mestre: rolagens secretas, só ele
  AUDIENCE_ALL = 'all'
  AUDIENCE_PLAYERS = 'players'
  AUDIENCE_DM = 'dm'
  AUDIENCES = [AUDIENCE_ALL, AUDIENCE_PLAYERS, AUDIENCE_DM].freeze

  belongs_to :schedule

  validates :kind,      presence: true, inclusion: { in: KINDS }
  validates :audience,  presence: true, inclusion: { in: AUDIENCES }
  validates :client_id, presence: true, uniqueness: { scope: :schedule_id }
  validate  :payload_must_be_hash

  before_validation :ensure_posted_at

  # Cronologia padrão da paginação reversa: mais recente primeiro.
  scope :recent_first, -> { order(posted_at: :desc, id: :desc) }

  # O que este espectador pode ler. O filtro é SQL, no servidor: esconder a
  # mensagem da equipe só no cliente não a esconderia de ninguém — ela já teria
  # chegado ao navegador do Mestre.
  scope :for_audiences, ->(allowed) {
    where(audience: Array(allowed).presence || [AUDIENCE_ALL])
  }

  # Cursor: tudo que veio antes deste timestamp + id (estável p/ ties).
  # Usado na paginação infinite-scroll (load older).
  scope :before_cursor, ->(posted_at, id) {
    return none if posted_at.blank?
    where('(posted_at, id) < (?, ?)', posted_at, id || 0)
  }

  private

  def ensure_posted_at
    self.posted_at ||= Time.current
  end

  def payload_must_be_hash
    errors.add(:payload, 'deve ser um Hash') unless payload.is_a?(Hash)
  end
end
