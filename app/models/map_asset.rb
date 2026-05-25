# frozen_string_literal: true

# Fase 2.6 — asset do Map Builder enviado pelo DM (textura/stamp/via).
#
# A imagem fica no ActiveStorage (`has_one_attached :image`), igual ao
# `Group#cover_image`. Stamps/brush layers do mapa referenciam o id deste
# registro (nunca embutem a imagem) → JSONB do mapa permanece pequeno.
#
# Autorização: criar/editar/remover é DM site-wide (controller admin);
# leitura serve a biblioteca pra todos os DMs (recurso compartilhado, como
# klasses). `enabled` esconde sem apagar (espelha `playable`).
class MapAsset < ApplicationRecord
  KINDS = %w[texture stamp path].freeze

  belongs_to :user, optional: true
  has_one_attached :image

  validates :name, presence: true, length: { maximum: 80 }
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :category, presence: true, length: { maximum: 40 }
  validates :color, format: { with: /\A#[0-9A-Fa-f]{6}\z/, message: 'deve ser hex #RRGGBB' },
                    allow_blank: true
  validate :image_present_and_valid

  scope :enabled, -> { where(enabled: true) }
  scope :of_kind, ->(k) { where(kind: k) }

  ALLOWED_CONTENT_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze
  MAX_BYTES = 5.megabytes

  private

  def image_present_and_valid
    unless image.attached?
      errors.add(:image, 'é obrigatória')
      return
    end
    if image.blob.byte_size.to_i > MAX_BYTES
      errors.add(:image, "muito grande (máx. #{MAX_BYTES / 1.megabyte} MB)")
    end
    unless ALLOWED_CONTENT_TYPES.include?(image.blob.content_type)
      errors.add(:image, 'tipo inválido (use PNG, JPEG, WebP ou GIF)')
    end
  end
end
