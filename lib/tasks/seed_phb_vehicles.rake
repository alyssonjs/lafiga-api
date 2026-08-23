# Semeia veiculos, arreios e selas do PHB ("Montarias e Veiculos", pg. 155).
#
# Motivo: a aba "Equipamentos" do compendio era uma casca — dizia "catalogo
# mundano indisponivel" e nao havia UM item de transporte no banco.
#
#   bundle exec rake dnd:seed_phb_vehicles
#   DRY_RUN=1 bundle exec rake dnd:seed_phb_vehicles
#
# Modelo: `kind: gear` + `category` propria (`vehicle_land`, `vehicle_water`,
# `tack`) — mesmo carve-out do `pack` e do `instrument`, sem tocar no enum.
# Montaria NAO entra aqui: ela ja existe como companion com ficha, e criar
# copias no catalogo geraria duas entidades com o mesmo nome.
namespace :dnd do
  # [nome, api_index, category, custo em CP, peso kg, props extras]
  PHB_VEHICLES = [
    # --- Veiculos terrestres (tracao) ---
    ['Biga',              'biga',              'vehicle_land',    25_000,  50.0, {}],
    ['Carroça',           'carroca',           'vehicle_land',     1_500, 100.0, {}],
    ['Carruagem',         'carruagem',         'vehicle_land',    10_000, 300.0, {}],
    ['Trenó',             'treno',             'vehicle_land',     2_000, 150.0, {}],
    # --- Veiculos aquaticos (peso nao se aplica; velocidade em km/h) ---
    ['Barco a remo',      'barco-a-remo',      'vehicle_water',    5_000,   nil, { 'speed_kmh' => 2.0 }],
    ['Barco de quilha',   'barco-de-quilha',   'vehicle_water',   300_000,  nil, { 'speed_kmh' => 1.5 }],
    ['Dracar',            'dracar',            'vehicle_water', 1_000_000,  nil, { 'speed_kmh' => 5.0 }],
    ['Galera',            'galera',            'vehicle_water', 3_000_000,  nil, { 'speed_kmh' => 6.5 }],
    ['Navio de guerra',   'navio-de-guerra',   'vehicle_water', 2_500_000,  nil, { 'speed_kmh' => 4.0 }],
    ['Veleiro',           'veleiro',           'vehicle_water', 1_000_000,  nil, { 'speed_kmh' => 3.0 }],
    # --- Arreios, selas e afins ---
    # `mount_slot` diz ONDE o item entra na montaria. `capacity_lb` do alforje e
    # HOUSERULE desta mesa: o PHB nao declara capacidade nenhuma para ele.
    ['Alforje',                  'alforje',                  'tack',   400,  4.0,  { 'mount_slot' => 'bags', 'capacity_lb' => 30 }],
    ['Armadura de montaria',     'armadura-de-montaria',     'tack',   nil,  nil,  { 'mount_slot' => 'barding', 'cost_multiplier' => 4, 'weight_multiplier' => 2 }],
    ['Freio e rédea',            'freio-e-redea',            'tack',   200,  0.5,  { 'mount_slot' => 'harness' }],
    ['Sela compacta',            'sela-compacta',            'tack',   500,  7.5,  { 'mount_slot' => 'saddle' }],
    ['Sela de viagem',           'sela-de-viagem',           'tack', 1_000, 12.5,  { 'mount_slot' => 'saddle' }],
    ['Sela militar',             'sela-militar',             'tack', 2_000, 15.0,  { 'mount_slot' => 'saddle' }],
    ['Sela exótica',             'sela-exotica',             'tack', 6_000, 20.0,  { 'mount_slot' => 'saddle' }],
    ['Ração (animal, 1 dia)',    'racao-animal-1-dia',       'tack',     5,  5.0,  {}],
    ['Estábulo (por dia)',       'estabulo-por-dia',         'tack',    50,  nil,  { 'service' => true }],
  ].freeze

  desc 'Semeia veiculos/arreios do PHB que faltam no catalogo (DRY_RUN=1 so relata)'
  task seed_phb_vehicles: :environment do
    dry = ENV['DRY_RUN'].present?
    criados = []
    pulados = []
    corrigidos = []

    PHB_VEHICLES.each do |name, api_index, category, cost_cp, weight_kg, extra|
      if (existente = Item.find_by(api_index: api_index))
        # Nao sobrescrever nome/custo/peso do que o mestre ja ajustou; corrigir
        # so a categoria, que e o que decide em qual aba o item aparece.
        fix = {}
        fix[:kind] = 'gear' if existente.kind.to_s != 'gear'
        fix[:category] = category if existente.category.to_s != category

        # Chaves ESTRUTURAIS de props (slot da montaria, capacidade) sao do
        # sistema, nao do mestre — preenche o que faltar sem tocar no resto.
        faltando = extra.reject { |k, _| (existente.props || {}).key?(k) }
        fix[:props] = (existente.props || {}).merge(faltando) if faltando.any?

        if fix.any?
          detalhe = fix.keys.map(&:to_s).join(', ')
          corrigidos << "#{api_index} (#{detalhe})"
          existente.update!(fix) unless dry
        else
          pulados << api_index
        end
        next
      end

      criados << api_index
      next if dry

      props = extra.dup
      # `EquipmentRules.item_cost_cp` le `props['cost_cp']` (padrao do catalogo).
      props['cost_cp'] = cost_cp if cost_cp

      Item.create!(
        api_index: api_index,
        name: name,
        kind: 'gear',
        category: category,
        weight_kg: weight_kg,
        props: props,
        source: 'PHB',
      )
    end

    puts "[dnd:seed_phb_vehicles]#{' DRY RUN —' if dry} #{criados.size} a criar, #{corrigidos.size} a corrigir, #{pulados.size} ja OK"
    puts "  criados: #{criados.join(', ')}" if criados.any?
    corrigidos.each { |c| puts "  corrigido: #{c}" }
  end
end
