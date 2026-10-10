# frozen_string_literal: true

# Um SETOR da campanha (L1.1; plano B3 e I6): um território da corrente de Argoba, com o estado, o território (que dá a
# CD do acampamento) e as duas pressões, a selvagem e a influência da ameaça, de 0 a 100.
class Setor < ApplicationRecord
  TIPOS = %w[assentamento selvagem vila_aliada estrada posto periferia distrito].freeze
  ESTADOS = %w[perdido disputado recuperado].freeze
  # plano A15: comum, infestado, amaldiçoado
  TERRITORIOS = %w[comum infestado amaldicoado].freeze

  belongs_to :campanha, inverse_of: :setores

  validates :chave, presence: true, uniqueness: { scope: :campanha_id }
  validates :nome, presence: true
  validates :tipo, inclusion: { in: TIPOS }
  validates :bioma, inclusion: { in: Regiao::BIOMAS }
  validates :estado, inclusion: { in: ESTADOS }
  validates :territorio, inclusion: { in: TERRITORIOS }
  validates :pressao_selvagem, :influencia,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :ordem, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :campanha_id }

  # A CD do teste de acampamento neste setor (plano A15), pela ficha da região.
  def cd_acampamento
    campanha.regiao.ficha['cd_acampamento'].fetch(territorio)
  end

  # o que a ficha da região diz deste setor (o tamanho do mapa, L1.2)
  def ficha
    campanha.regiao.ficha.dig('campanha', 'setores').find { |s| s['chave'] == chave } || {}
  end
end
