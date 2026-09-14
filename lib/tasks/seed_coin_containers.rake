# frozen_string_literal: true

namespace :dnd do
  desc 'Declara a capacidade de MOEDAS da Algibeira do catalogo (idempotente)'
  # PHB cap. 5: a algibeira leva 1/5 de pe cubico ou 6 lb de equipamento, e 50
  # moedas pesam 1 lb — cabem 300 moedas.
  #
  # A mesa quis a algibeira como a aljava das moedas: o jogador esconde dinheiro
  # numa algibeira dentro da mochila. O recipiente e DECLARADO no catalogo
  # (`coin_capacity`), nunca deduzido do nome — "bolsa PO x120" e dinheiro solto
  # e "Bolsa de componentes" e foco, e nenhum dos dois guarda moedas.
  #
  # ⚠️ Constante com nome proprio: as de rake vivem no escopo global, e
  # `CONTAINERS` ja e da rake da aljava.
  COIN_CONTAINERS = [
    # [nome, api_index, custo_cp, peso_kg, capacidade_em_moedas]
    ['Algibeira', 'algibeira', 50, 0.5, 300],
  ].freeze

  task seed_coin_containers: :environment do
    criados = []
    completados = []
    ja_ok = 0

    COIN_CONTAINERS.each do |nome, idx, custo, peso, capacidade|
      item = Item.find_by(api_index: idx)

      if item.nil?
        Item.create!(
          api_index: idx, name: nome, kind: 'gear', category: 'equipment',
          props: { 'coin_capacity' => capacidade, 'cost_cp' => custo },
          weight_kg: peso,
        )
        criados << idx
        next
      end

      props = (item.props || {}).dup
      # NAO sobrescreve o que o mestre ja declarou no editor — so completa.
      if props['coin_capacity'].present?
        ja_ok += 1
        next
      end

      props['coin_capacity'] = capacidade
      item.update!(props: props)
      completados << idx
    end

    puts "[dnd:seed_coin_containers] criados=#{criados.size} completados=#{completados.size} ja_ok=#{ja_ok}"
    puts "  criados: #{criados.join(', ')}" if criados.any?
    puts "  completados: #{completados.join(', ')}" if completados.any?
  end
end
