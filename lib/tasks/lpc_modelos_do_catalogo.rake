# Grava o MODELO LPC de cada armadura e escudo do catálogo em `items.props.lpc_pecas`.
#
#   bin/rails lpc:modelos_do_catalogo            # DRY RUN (padrão)
#   APPLY=1 bin/rails lpc:modelos_do_catalogo    # grava
#
# ## Por que existe
#
# 05/10, a mesa: "os designs das armaduras devem estar atrelados às armaduras de fato que vão ser equipadas… não vamos
# adotar o modelo por nome, é muito vago. Vamos associar os modelos pelo banco de dados". O desenho de cada armadura
# passa a ser DADO do item do catálogo — o Mestre troca no editor do catálogo, o jogador pinta o exemplar dele.
# O `equipment:import_items` já semeia as do `equipment.yml`; esta rake cobre as que só existem no banco (o Escudo de
# Madeira, o Escudo Grande, o Escudo +1…).
#
# ## Ordem de decisão (`LpcModelosDoCatalogo.para`, nunca pelo nome)
#
#   1. o `api_index` EXATO no `config/lpc_modelos.yml`;
#   2. a CATEGORIA do banco (light → couro, medium → camisa de malha, heavy → placas, shield → o escudo); o escudo
#      sem categoria, pelo `kind`.
#
# A armadura sem índice conhecido e sem categoria sai na seção "SEM MODELO": o Mestre escolhe no catálogo.
# Idempotente: nunca sobrescreve um `lpc_pecas` já presente (a escolha do Mestre).
namespace :lpc do
  desc 'Grava o modelo LPC das armaduras e escudos do catálogo (config/lpc_modelos.yml). APPLY=1 grava.'
  task modelos_do_catalogo: :environment do
    aplicar = ENV['APPLY'].to_s == '1'
    puts(aplicar ? '== APLICANDO ==' : '== DRY RUN (use APPLY=1 para gravar) ==')

    alvo = Item.where(kind: %w[armor shield]).or(Item.where(category: 'shield')).order(:kind, :name)
    rotulo = ->(pecas) { pecas.map { |p| [p['parte'], p['cor']&.map { |m, c| "#{m}=#{c}" }&.join(',')].compact.join(' ') }.join(' + ') }
    gravados = []
    mantidos = []
    sem_modelo = []

    alvo.find_each do |item|
      props = item.props || {}
      if props['lpc_pecas'].present?
        mantidos << item
        next
      end
      modelo = LpcModelosDoCatalogo.para(item)
      unless modelo
        sem_modelo << item
        next
      end
      gravados << [item, modelo]
      item.update!(props: props.merge('lpc_pecas' => modelo)) if aplicar
    end

    puts "\n#{aplicar ? 'GRAVADOS' : 'A GRAVAR'} (#{gravados.size}):"
    gravados.each { |item, modelo| puts "  #{item.api_index} (#{item.name}, #{item.kind}/#{item.category || '-'}): #{rotulo.call(modelo)}" }
    puts "\nJÁ TÊM MODELO — escolha do Mestre, mantida (#{mantidos.size}):"
    mantidos.each { |item| puts "  #{item.api_index} (#{item.name}): #{rotulo.call(EquipmentRules.sanitize_lpc_pecas(item.props['lpc_pecas']) || [])}" }
    puts "\nSEM MODELO — sem índice conhecido nem categoria; o Mestre escolhe no catálogo (#{sem_modelo.size}):"
    sem_modelo.each { |item| puts "  #{item.api_index} (#{item.name}, #{item.kind})" }
  end
end
