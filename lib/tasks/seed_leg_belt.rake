# Semeia o CINTO DE PERNA canonico — o coldre de coxa.
#
#   bundle exec rake dnd:seed_leg_belt            # DRY RUN
#   APPLY=1 bundle exec rake dnd:seed_leg_belt    # aplica
#
# A mecanica sem um item no catalogo obriga o Mestre a criar um a mao so para
# experimentar. Este e o de referencia: 1 vaga livre (arma pequena) + 1 de
# consumivel, o suficiente para "adaga na coxa e pocao ao lado".
#
# Idempotente pelo `api_index`; nao mexe no item se ele ja existir.
namespace :dnd do
  desc 'Cria o cinto de perna canonico (coldre de coxa). APPLY=1 aplica.'
  task seed_leg_belt: :environment do
    aplicar = ENV['APPLY'].to_s == '1'
    puts(aplicar ? '== APLICANDO ==' : '== DRY RUN (use APPLY=1 para aplicar) ==')

    slug = 'coldre-de-coxa'
    existente = Item.find_by(api_index: slug)
    if existente
      puts "  ja existe: ##{existente.id} #{existente.name.inspect}"
      next
    end

    atributos = {
      api_index: slug,
      name: 'Coldre de coxa',
      kind: 'gear',
      category: 'belt_leg',
      sub_category: 'belt_leg',
      weight_kg: 0.3,
      value_gp: 3,
      description: 'Correia de couro presa à coxa. Leva o que se saca depressa: '\
                   'uma arma pequena e um frasco.',
      props: {
        'equip_slot' => 'belt_leg_left',
        'belt_free_slots' => 1,
        'belt_consumable_slots' => 1,
      },
    }

    puts "  criaria: #{atributos[:name].inspect} (#{slug}) — 1 livre + 1 consumível"
    Item.create!(atributos) if aplicar
    puts aplicar ? '  OK' : '  (nada gravado)'
  end
end
