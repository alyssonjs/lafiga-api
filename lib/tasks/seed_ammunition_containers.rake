# frozen_string_literal: true

namespace :dnd do
  desc 'Semeia os RECIPIENTES de municao do PHB e declara a capacidade (idempotente)'
  # PHB cap. 5: "sacar a municao de uma aljava, BOLSA, ou outro recipiente faz
  # parte do ataque". A Aljava guarda ate 20 flechas; o Porta Virotes, ate 20
  # virotes de besta.
  #
  # A Aljava JA existe no catalogo com `equipment_slot: quiver` e
  # `ammunition_types` — o que faltava era `ammunition_capacity`. Este rake
  # completa o que falta sem sobrescrever o que o mestre editou.
  CONTAINERS = [
    # [nome, api_index, custo_cp, peso_kg, aceita, capacidade]
    ['Aljava',            'aljava',            100, 0.5, %w[flecha],                        20],
    ['Porta Virotes',     'porta-virotes',     100, 0.5, %w[virote],                        20],
    ['Bolsa de Munição',  'bolsa-de-municao',   50, 0.5, %w[pedra-de-funda agulha-de-zarabatana], 20],
  ].freeze

  task seed_ammunition_containers: :environment do
    criados = []
    completados = []
    ja_ok = 0

    CONTAINERS.each do |nome, idx, custo, peso, aceita, capacidade|
      item = Item.find_by(api_index: idx)

      if item.nil?
        Item.create!(
          api_index: idx, name: nome, kind: 'gear',
          props: {
            'equipment_slot' => 'quiver',
            'ammunition_types' => aceita,
            'ammunition_capacity' => capacidade,
            'cost_cp' => custo,
          },
          weight_kg: peso,
        )
        criados << idx
        next
      end

      props = (item.props || {}).dup
      antes = props.dup
      # NAO sobrescreve o que o mestre ja declarou — so completa o que falta.
      props['equipment_slot'] ||= 'quiver'
      props['ammunition_types'] = aceita if Array(props['ammunition_types']).empty?
      props['ammunition_capacity'] ||= capacidade

      if props == antes
        ja_ok += 1
      else
        item.update!(props: props)
        completados << "#{idx} (#{(props.keys - antes.keys).join(', ').presence || 'valores'})"
      end
    end

    puts "[dnd:seed_ammunition_containers] criados=#{criados.size} completados=#{completados.size} ja_ok=#{ja_ok}"
    puts "  criados: #{criados.join(', ')}" if criados.any?
    completados.each { |c| puts "  completado: #{c}" }
  end
end
