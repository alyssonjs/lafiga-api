# frozen_string_literal: true

# Onde um personagem ESTÁ (L0.8; plano B3): uma mesa (de qualquer modo) e, dentro dela, um mapa. Um lugar por
# personagem: quem muda é o `Presencas::Entra`, que tira o personagem de onde ele estava.
class Presenca < ApplicationRecord
  belongs_to :character
  belongs_to :schedule
  belongs_to :battle_map, optional: true

  validates :character_id, uniqueness: true
  validates :batimento_em, presence: true
end
