# frozen_string_literal: true

# NPC BÁSICO do catálogo — o que o Mestre monta uma vez e reusa em toda mesa:
# um guarda, um taverneiro, um bandido. CA, PV, um ataque.
#
# ⚠️ **Só o Mestre vê.** Não há endpoint público: é bastidor de mesa, não
# conteúdo de jogador. Diferente do companheiro (que o jogador escolhe) e do
# monstro (que aparece no compêndio para todos).
class BasicNpc < ApplicationRecord
  STAT_KEYS = %w[str dex con int wis cha].freeze
  SPEED_MODES = %w[walk fly swim climb burrow].freeze

  validates :slug, presence: true, uniqueness: true
  validates :name, presence: true
  validates :hp, :ac, numericality: { greater_than_or_equal_to: 0 }

  before_validation :normalizar_slug
  before_save :normalizar_blocos

  scope :busca, lambda { |q|
    next if q.blank?

    termo = "%#{q.to_s.strip.downcase}%"
    where('LOWER(name) LIKE :t OR LOWER(role) LIKE :t OR LOWER(slug) LIKE :t', t: termo)
  }

  # Shape que a SESSÃO consome — o mesmo do formulário simples de NPC, para
  # "puxar do catálogo" ser cópia direta, sem tradutor pelo meio.
  def as_session_npc_json
    {
      id: slug,
      name: name,
      role: role,
      hp: hp,
      maxHp: hp,
      ac: ac,
      initiativeBonus: initiative_bonus,
      speed: (speed_modes || {})['walk'],
      speedModes: speed_modes.presence || {},
      stats: stats.presence || STAT_KEYS.index_with { 10 },
      attacks: attacks || [],
      notes: notes,
      tokenImageUrl: token_image_url,
    }
  end

  # Path relativo, como o do monstro: o endpoint do `map_assets` já serve o blob
  # com cache imutável e sem gate de DM.
  def token_image_url
    return nil if token_map_asset_id.blank?

    "/api/v1/admin/map_assets/#{token_map_asset_id}/image?v=#{token_map_asset_id}"
  end

  private

  def normalizar_slug
    self.slug = slug.presence || name.to_s.parameterize
    self.slug = slug.to_s.parameterize
  end

  # ⚠️ Chave desconhecida em `stats`/`speed_modes` viraria dado morto que o
  # front nunca lê. Filtra na escrita; o leitor não precisa desconfiar.
  def normalizar_blocos
    self.stats = (stats || {}).slice(*STAT_KEYS).transform_values(&:to_i)
    modos = (speed_modes || {}).slice(*SPEED_MODES).transform_values(&:to_i)
    self.speed_modes = modos.reject { |_, v| v <= 0 }
    self.attacks = Array(attacks).map { |a| a.respond_to?(:to_h) ? a.to_h : a }
  end
end
