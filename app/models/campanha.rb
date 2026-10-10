# frozen_string_literal: true

# A CAMPANHA REGIONAL de um mundo (L1.1; plano B3, I1 e I5; GDD §86): a região, a ameaça e a etapa do arco. Quem cria é
# `Campanhas::Inicia`, pela ficha da região.
class Campanha < ApplicationRecord
  belongs_to :mundo
  belongs_to :regiao
  has_many :setores, -> { order(:ordem) }, dependent: :delete_all, inverse_of: :campanha

  validates :chave, presence: true, uniqueness: { scope: :mundo_id }
  validates :nome, :ameaca, presence: true
  validate :etapa_do_arco

  private

  # a etapa é uma das etapas do arco, na ficha da região
  def etapa_do_arco
    etapas = regiao ? Array(regiao.ficha.dig('campanha', 'etapas')) : []
    errors.add(:etapa, :inclusion, value: etapa) unless etapas.include?(etapa)
  end
end
