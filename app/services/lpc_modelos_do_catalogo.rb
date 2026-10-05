# frozen_string_literal: true

require 'yaml'

# O MODELO LPC padrão das armaduras e escudos do catálogo (05/10) — o `config/lpc_modelos.yml`, pelo `api_index`
# EXATO ou pela CATEGORIA do banco, nunca pelo nome. Só SEMEIA `items.props.lpc_pecas` (a rake
# `lpc:modelos_do_catalogo` e o `equipment:import_items`); quem lê o modelo é `EquipmentRules.lpc_pecas`, do banco.
module LpcModelosDoCatalogo
  PATH = Rails.root.join('config', 'lpc_modelos.yml')

  class << self
    def dados
      @dados ||= YAML.safe_load(File.read(PATH)) || {}
    end

    # O modelo de um `api_index` (armadura ou escudo), já no formato gravado (`[{ 'parte' =>, 'cor' => }]`).
    def do_indice(api_index)
      return nil if api_index.blank?

      bruto = dados.dig('armaduras', api_index.to_s) || dados.dig('escudos', api_index.to_s)
      EquipmentRules.sanitize_lpc_pecas(bruto)
    end

    # O modelo de um item do catálogo: o do índice; sem ele, o da categoria (light/medium/heavy/shield) — o escudo
    # sem categoria, pelo `kind`; nil = sem modelo (a armadura sem peso conhecido: o Mestre escolhe).
    def para(item)
      return nil unless item

      categoria = item.category.presence || ('shield' if item.kind.to_s == 'shield')
      do_indice(item.api_index) || do_indice(dados.dig('por_categoria', categoria.to_s))
    end
  end
end
