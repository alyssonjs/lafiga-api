# frozen_string_literal: true

# Relato de bug enviado pelo usuário via botão "Relatar bug" no header.
#
# Autorização: qualquer usuário autenticado cria (controller player) e vê os
# próprios; DM/Admin site-wide vê todos (controller admin) — mesmo padrão de
# visibilidade role-aware de `CampaignNote`. Anexos (screenshots) opcionais via
# ActiveStorage, validados por tipo/tamanho como `MapAsset#image`.
class BugReport < ApplicationRecord
  belongs_to :user
  has_many_attached :attachments

  # bug = relato de jogador; improvement = melhoria solicitada pelo DM (form DM-only).
  enum kind: { bug: 0, improvement: 1 }, _prefix: :kind
  enum severity: { low: 0, medium: 1, high: 2, critical: 3 }, _prefix: :severity
  # aberto (default) → em_progresso → feito | ajustado; descartado = não será feito.
  enum status: { aberto: 0, em_progresso: 1, feito: 2, ajustado: 3, descartado: 4 }, _prefix: :status

  validates :title, presence: true, length: { maximum: 200 }
  validates :description, presence: true, length: { maximum: 5_000 }
  validates :steps_to_reproduce, length: { maximum: 5_000 }, allow_blank: true
  validate :attachments_valid

  scope :recent_first, -> { order(created_at: :desc) }

  # DM/Admin site-wide vê todos; jogador comum só os próprios. Mesma assinatura
  # de `CampaignNote.visible_to` (sem `visibility` — bug report é privado ao autor
  # + visível ao mestre).
  scope :visible_to, ->(user) { Group.user_is_dm?(user) ? all : where(user_id: user&.id) }

  ALLOWED_CONTENT_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze
  MAX_BYTES = 5.megabytes
  MAX_ATTACHMENTS = 5

  private

  # Anexos são OPCIONAIS (bug pode não ter screenshot); quando presentes, valida
  # quantidade, tamanho e tipo — espelha `MapAsset#image_present_and_valid` mas
  # sem exigir presença.
  def attachments_valid
    return unless attachments.attached?

    if attachments.size > MAX_ATTACHMENTS
      errors.add(:attachments, "máximo de #{MAX_ATTACHMENTS} arquivos")
    end

    attachments.each do |att|
      blob = att.blob
      next unless blob

      if blob.byte_size.to_i > MAX_BYTES
        errors.add(:attachments, "arquivo muito grande (máx. #{MAX_BYTES / 1.megabyte} MB)")
      end
      unless ALLOWED_CONTENT_TYPES.include?(blob.content_type)
        errors.add(:attachments, 'tipo inválido (use PNG, JPEG, WebP ou GIF)')
      end
    end
  end
end
