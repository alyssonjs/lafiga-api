# Semeia os consumiveis do PHB que faltam e CLASSIFICA os que ja existem no
# vocabulario de sub-tipo da aba Consumiveis.
#
#   bundle exec rake dnd:seed_phb_consumables            # aplica
#   DRY_RUN=1 bundle exec rake dnd:seed_phb_consumables  # so relata
#
# Idempotente: casa por `api_index`, nunca duplica, nunca sobrescreve nome,
# custo ou peso de item existente, e so escreve `category` onde ela e NULL.
#
# NULL != string vazia, de proposito. NULL = nunca foi tocada. Vazia = o mestre
# escolheu "Outros" no editor, o que LIMPA a categoria. Tratar as duas igual
# fazia o proximo deploy desfazer essa escolha em silencio.
#
# Sub-tipos (`Item.category` com `kind: consumable`):
#   potion      Pocoes
#   poison      Venenos
#   alchemical  Alquimicos — acido, fogo alquimico, agua benta, antidoto
#   supply      Suprimentos — racao, tocha, vela, oleo, cantil
#   (nil)       Outros
namespace :dnd do
  # [nome, api_index, category, custo em PO, peso em kg]
  # Precos e pesos da tabela EQUIPAMENTO do PHB pt-BR (pg. 149).
  PHB_CONSUMABLES = [
    ['Ácido (vidro)',            'acido-vidro',             'alchemical',  25,   0.5],
    ['Água benta (frasco)',      'agua-benta-frasco',       'alchemical',  25,   0.5],
    ['Antídoto (vidro)',         'antidoto-vidro',          'alchemical',  50,   0.0],
    ['Fogo alquímico (frasco)',  'fogo-alquimico-frasco',   'alchemical',  50,   0.5],
    ['Óleo (frasco)',            'oleo-frasco',             'supply',       0.1, 0.5],
    ['Veneno básico (frasco)',   'veneno-basico-frasco',    'poison',     100,   0.0],
  ].freeze

  # Itens que JA existem e estao sem sub-tipo. Mapeados por `api_index` EXATO,
  # nunca por heuristica de nome: "Amu. Furacão" e "Coração de Elemental Vento"
  # sao homebrew do mestre e adivinhar o sub-tipo deles seria inventar.
  CONSUMABLE_BACKFILL = {
    'agua-benta-x2'  => 'alchemical',
    'cantil'         => 'supply',
    'cantil-agua'    => 'supply',
    'cantil-bebida'  => 'supply',
    'racao'          => 'supply',
    'tocha'          => 'supply',
    'tocha-2'        => 'supply',
    'tochas'         => 'supply',
    'velas'          => 'supply',
  }.freeze

  desc 'Semeia consumiveis do PHB e classifica os existentes (DRY_RUN=1 so relata)'
  task seed_phb_consumables: :environment do
    dry = ENV['DRY_RUN'].present?
    criados = []
    pulados = []
    classificados = []

    PHB_CONSUMABLES.each do |name, api_index, category, cost_gp, weight_kg|
      if (existente = Item.find_by(api_index: api_index))
        if existente.category.nil?
          classificados << "#{api_index} -> #{category}"
          existente.update!(category: category) unless dry
        else
          pulados << "#{api_index} (ja tem category=#{existente.category.inspect})"
        end
        next
      end

      criados << "#{api_index} (#{category})"
      next if dry

      Item.create!(
        api_index: api_index,
        name: name,
        kind: 'consumable',
        category: category,
        weight_kg: weight_kg,
        props: { 'cost_cp' => (cost_gp.to_f * 100).round },
        source: 'PHB',
      )
    end

    CONSUMABLE_BACKFILL.each do |api_index, category|
      item = Item.find_by(api_index: api_index)
      next pulados << "#{api_index} (nao existe)" if item.nil?
      next pulados << "#{api_index} (category=#{item.category.inspect} — escolha do mestre)" unless item.category.nil?

      classificados << "#{api_index} -> #{category}"
      item.update!(category: category) unless dry
    end

    puts "[dnd:seed_phb_consumables]#{' DRY RUN —' if dry} #{criados.size} criado(s), #{classificados.size} classificado(s), #{pulados.size} ja OK"
    criados.each       { |c| puts "  criado: #{c}" }
    classificados.each { |c| puts "  classificado: #{c}" }

    # Relatorio: o que fica em "Outros" e porque. Nao adivinho o sub-tipo de
    # homebrew — o mestre escolhe no editor.
    sem_tipo = Item.where(kind: 'consumable')
                   .where("category IS NULL OR TRIM(category) = ''")

    if sem_tipo.any?
      puts "  [aviso] #{sem_tipo.count} consumivel(is) ficam em \"Outros\" (homebrew sem sub-tipo):"
      sem_tipo.order(:name).each { |i| puts "    ##{i.id} #{i.name.inspect} (#{i.api_index})" }
    end
  end
end
