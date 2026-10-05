# frozen_string_literal: true

require 'yaml'

module Subclasses
  # Leitor ÚNICO e memoizado do `config/subclass_overrides.yml`.
  #
  # ⚠️ O arquivo tem ~5900 linhas e era relido do disco A CADA REQUEST — em
  # `ClassRules.available_subclasses`, uma vez por sub-classe da classe, numa
  # leitura que a criação de personagem faz. Somando `SubclassHpBonus`, o
  # agregador de magias e o import, eram quatro leitores com quatro memoizações
  # (ou nenhuma) do mesmo arquivo.
  #
  # É arquivo de CONFIGURAÇÃO: muda por deploy, não em runtime. Memoizar no
  # processo é o certo — e `recarrega!` existe para os specs que o mexem.
  module OverridesYaml
    CAMINHO = 'subclass_overrides.yml'

    module_function

    def dados
      @dados ||= carrega
    end

    def recarrega!
      @dados = nil
      dados
    end

    def carrega
      caminho = Rails.root.join('config', CAMINHO)
      return {} unless File.exist?(caminho)

      YAML.load_file(caminho) || {}
    rescue StandardError => e
      # ⚠️ Degrada para vazio em vez de derrubar: sem isto, um YAML partido
      # levaria junto a criação de personagem inteira, e não só a regra da
      # sub-classe que ele descreve.
      Rails.logger.warn("Subclasses::OverridesYaml: falha ao ler #{CAMINHO}: #{e.class}: #{e.message}")
      {}
    end
  end
end
