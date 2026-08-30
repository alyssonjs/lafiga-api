# Declara USOS LIMITADOS nos itens do catalogo que gastam por uso, e semeia o
# Kit de Primeiros Socorros, que faltava.
#
#   bundle exec rake dnd:seed_item_uses            # aplica
#   DRY_RUN=1 bundle exec rake dnd:seed_item_uses  # so relata
#
# Idempotente: casa por `api_index`, so escreve `props['uses_max']` quando ele
# ainda nao existe (um mestre que ajustou o teto a mao nao e sobrescrito).
#
# Sobre recarga: kit NAO tem `uses_recharge`. Descanso nao repoe ataduras — o
# kit acaba e se compra outro. O token `short`/`long` existe para item magico.
namespace :dnd do
  # [nome, api_index, category, custo em PO, peso em kg, usos, recarga]
  ITEM_USES_SEED = [
    ['Kit de Primeiros Socorros', 'kit-de-primeiros-socorros', 'kit', 5, 1.5, 10, nil],
    # Caixa de fogo (PHB: 5 pp, 0,5 kg). O livro NAO da um numero de usos — a
    # isca e o pederneira gastam-se, mas a tabela nao conta. Dez e HOUSERULE
    # desta mesa, e a evidencia esta nas fichas: seis jogadores criaram a
    # propria entrada de catalogo chamada "caixa de fogo x10" para contar o que
    # gastavam, porque nao havia onde. O teto vive so aqui — o mestre muda num
    # sitio e vale para todos.
    ['Caixa de fogo', 'caixa-de-fogo', 'equipment', 0.5, 0.5, 10, nil],
  ].freeze

  desc 'Semeia o Kit de Primeiros Socorros e declara usos limitados (DRY_RUN=1 so relata)'
  task seed_item_uses: :environment do
    dry = ENV['DRY_RUN'].present?
    criados = []
    marcados = []
    pulados = []

    ITEM_USES_SEED.each do |name, api_index, category, cost_gp, weight_kg, usos, recarga|
      item = Item.find_by(api_index: api_index)

      if item.nil?
        criados << api_index
        next if dry

        Item.create!(
          api_index: api_index,
          name: name,
          kind: 'tool',
          category: category,
          weight_kg: weight_kg,
          props: {
            'cost_cp' => (cost_gp.to_f * 100).round,
            'uses_max' => usos,
            **(recarga ? { 'uses_recharge' => recarga } : {}),
          },
          source: 'PHB',
        )
        next
      end

      props = item.props || {}
      if props['uses_max'].present?
        pulados << "#{api_index} (ja tem uses_max=#{props['uses_max']})"
        next
      end

      marcados << "#{api_index} -> uses_max=#{usos}"
      next if dry

      item.update!(props: props.merge(
        'uses_max' => usos,
        **(recarga ? { 'uses_recharge' => recarga } : {}),
      ))
    end

    puts "[dnd:seed_item_uses]#{' DRY RUN —' if dry} #{criados.size} criado(s), #{marcados.size} marcado(s), #{pulados.size} ja OK"
    puts "  criados: #{criados.join(', ')}" if criados.any?
    marcados.each { |m| puts "  marcado: #{m}" }
    pulados.each  { |p| puts "  pulado: #{p}" }

    # Relatorio, sem tocar: o mestre codificou a contagem de usos NO NOME
    # ("kit SOS x10") porque nao havia contador. Agora ha — mas quantos usos
    # cada variante tem e decisao dele, nao minha (x3 pode ser 3 usos ou 3 kits).
    # "kit" E "sos" no nome: so `%sos%` casava "Tiara dos VerSOS".
    homebrew = Item.where("LOWER(name) LIKE ? AND LOWER(name) LIKE ?", '%kit%', '%sos%')
                   .where("props IS NULL OR NOT (props ? 'uses_max')")
    if homebrew.any?
      puts "  [aviso] #{homebrew.count} entrada(s) homebrew de kit sem uses_max — declarar o teto a mao no admin:"
      homebrew.order(:name).each { |i| puts "    ##{i.id} #{i.name.inspect} (#{i.api_index})" }
    end
  end
end
