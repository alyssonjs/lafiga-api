# frozen_string_literal: true

# Vínculo sessão ↔ mapa. O mapa ATIVO continua em `schedules.battle_map_id`;
# aqui ficam todos os mapas que o mestre pode alternar durante a sessão.
class ScheduleBattleMap < ApplicationRecord
  belongs_to :schedule
  belongs_to :battle_map

  validates :battle_map_id, uniqueness: { scope: :schedule_id }

  scope :ordered, -> { order(:position, :id) }
end
