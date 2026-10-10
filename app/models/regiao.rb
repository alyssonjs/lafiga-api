# frozen_string_literal: true

# Uma REGIÃO de Lafiga (L1.1; plano A14 e B3). A linha guarda a identidade; a ficha (biomas, recursos, fauna, CDs, a
# campanha) mora no yml e quem lê é `Regioes::Ficha`. A ficha manda: `sincroniza!` traz o nome e o reino de lá.
class Regiao < ApplicationRecord
  # O vocabulário de bioma do projeto, o mesmo de `front-lafiga/src/app/data/biomes.ts` (lá está a história das três
  # listas que não conversavam). O `subclass_overrides.yml` grava os mesmos ids.
  BIOMAS = %w[artico costa colina deserto floresta montanha pantano planicie subterraneo urbano aquatico].freeze

  has_many :campanhas, dependent: :restrict_with_exception

  validates :chave, presence: true, uniqueness: true
  validates :nome, :reino, presence: true

  # A linha da região pela ficha: cria se falta, corrige o nome e o reino se a ficha mudou.
  def self.sincroniza!(chave)
    ficha = Regioes::Ficha.de(chave)
    regiao = find_or_initialize_by(chave: ficha['chave'])
    regiao.update!(nome: ficha['nome'], reino: ficha['reino'])
    regiao
  end

  def ficha
    Regioes::Ficha.de(chave)
  end
end
