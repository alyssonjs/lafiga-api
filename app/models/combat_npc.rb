# NPC vivo dentro de uma sessão (Schedule). Vida-curta: nasce quando o DM
# adiciona ao tracker e morre ao fim da sessão. O catálogo persistente de
# NPCs reutilizáveis da campanha entra na Fase 2.
#
# Atributos "estáveis" do NPC (stats, attacks, equipment) ficam aqui. Os
# atributos "vivos" do combate (initiative, position, conditions) ficam em
# `combat_combatants` via associação polimórfica `combatable`.
#
# `defeated_at` marca derrota sem deletar — preserva log e permite "ressurreição"
# pelo DM (set defeated_at = nil).
class CombatNpc < ApplicationRecord
  belongs_to :schedule
  has_many :combat_combatants, as: :combatable, dependent: :destroy

  validates :name, presence: true
  validates :hp_current, :hp_max, :ac, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  STAT_KEYS = %w[str dex con int wis cha].freeze
  validate  :stats_keys_valid

  scope :alive,    -> { where(defeated_at: nil) }
  scope :defeated, -> { where.not(defeated_at: nil) }

  def alive?
    defeated_at.nil?
  end

  def defeat!
    return self unless alive?
    update!(defeated_at: Time.current)
    self
  end

  def revive!
    return self if alive?
    update!(defeated_at: nil)
    self
  end

  private

  def stats_keys_valid
    return if stats.blank?
    return errors.add(:stats, 'deve ser um Hash') unless stats.is_a?(Hash)
    invalid = stats.keys.map(&:to_s) - STAT_KEYS
    errors.add(:stats, "chaves inválidas: #{invalid.join(', ')}") if invalid.any?
  end
end
