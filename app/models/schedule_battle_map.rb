# frozen_string_literal: true

# Vínculo sessão ↔ mapa. O mapa ATIVO continua em `schedules.battle_map_id`;
# aqui ficam todos os mapas que o mestre pode alternar durante a sessão.
class ScheduleBattleMap < ApplicationRecord
  belongs_to :schedule
  belongs_to :battle_map

  validates :battle_map_id, uniqueness: { scope: :schedule_id }
  # A nevoa saiu do mapa para ca; sem espelhar a validacao de formato, a camada
  # aceitaria uma grade torta que o mapa recusava e o render quebraria.
  validate :fog_matches_map_dimensions

  scope :ordered, -> { order(:position, :id) }

  private

  def fog_matches_map_dimensions
    return if fog.nil?
    unless fog.is_a?(Array)
      errors.add(:fog, 'deve ser uma lista ou nulo')
      return
    end
    return if fog.empty?

    map = battle_map
    return if map.nil?

    if fog.size != map.height
      errors.add(:fog, "linhas (#{fog.size}) != altura do mapa (#{map.height})")
      return
    end
    fog.each_with_index do |row, idx|
      next if row.is_a?(Array) && row.size == map.width

      errors.add(:fog, "linha #{idx} malformada")
      return
    end
  end
end
