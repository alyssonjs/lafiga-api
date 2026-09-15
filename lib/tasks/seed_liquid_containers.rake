# frozen_string_literal: true

namespace :dnd do
  desc 'Declara a capacidade de LÍQUIDO dos recipientes do catálogo (idempotente)'
  # PHB cap. 5, tabela "Capacidade de Recipientes" (edição em português). A mesa
  # quis o Barril como recipiente de verdade: guardar e tirar água (ou outro
  # líquido) pela ficha do item, pesando 1 kg por litro (14/09/2026).
  #
  # ⚠️ Só COMPLETA: não cria item (o catálogo do livro já os tem) e não
  # sobrescreve o teto que o mestre ajustou no editor.
  #
  # ⚠️ Constante com nome próprio: as de rake vivem no escopo global.
  LIQUID_CONTAINERS = [
    # [api_index, litros]
    ['barril', 160],
    ['balde', 12],
    ['jarra', 5],
    ['panela-de-ferro', 4],
    ['cantil', 2],
    ['garrafa-de-vidro', 0.75],
    ['caneca', 0.5],
    ['frasco', 0.12],
  ].freeze

  task seed_liquid_containers: :environment do
    completados = []
    ausentes = []
    ja_ok = 0

    LIQUID_CONTAINERS.each do |idx, litros|
      item = Item.find_by(api_index: idx)
      if item.nil?
        ausentes << idx
        next
      end

      props = (item.props || {}).dup
      if props['liquid_capacity_l'].present?
        ja_ok += 1
        next
      end

      props['liquid_capacity_l'] = litros
      item.update!(props: props)
      completados << idx
    end

    puts "[dnd:seed_liquid_containers] completados=#{completados.size} ja_ok=#{ja_ok} ausentes=#{ausentes.size}"
    puts "  completados: #{completados.join(', ')}" if completados.any?
    puts "  ausentes: #{ausentes.join(', ')}" if ausentes.any?
  end
end
