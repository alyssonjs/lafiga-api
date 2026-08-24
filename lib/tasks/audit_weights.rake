# Auditoria de PESOS do catalogo — relatorio, nunca escreve.
#
#   bundle exec rake dnd:audit_weights
#
# O canonico e KG (`items.weight_kg`, valores do PHB pt-BR). O serializer
# converte para lb (x2, convencao do livro) na fronteira. Este rake existe
# porque a coluna ja carregou DOIS entendimentos ("e kg" / "e lb") — se um
# import futuro gravar lb por engano, os numeros saem ~2x maiores e este
# relatorio e o jeito de perceber ANTES do jogador reclamar da carga.
namespace :dnd do
  # Pesos canonicos (kg) de itens do PHB que qualquer import re-toca. Se um
  # deles divergir, alguem gravou na unidade errada.
  WEIGHT_SENTINELS = {
    'ferramentas-de-ferreiro' => 4.0,
    'kit-de-primeiros-socorros' => 1.5,
    'acido-vidro' => 0.5,
  }.freeze

  desc 'Relata pesos suspeitos no catalogo (nao escreve nada)'
  task audit_weights: :environment do
    com_peso = Item.where.not(weight_kg: nil)
    puts "[dnd:audit_weights] #{com_peso.count} itens com peso, #{Item.where(weight_kg: nil).count} sem"

    divergentes = WEIGHT_SENTINELS.filter_map do |api_index, esperado|
      item = Item.find_by(api_index: api_index)
      next if item.nil? || item.weight_kg.to_f == esperado

      "#{api_index}: esperado #{esperado} kg, gravado #{item.weight_kg}"
    end
    if divergentes.any?
      puts "  [ALERTA] sentinelas divergentes — provavel import em lb:"
      divergentes.each { |d| puts "    #{d}" }
    else
      puts "  sentinelas OK (#{WEIGHT_SENTINELS.size})"
    end

    # Item de mochila acima de 60 kg e quase sempre unidade errada ou typo
    # (a excecao legitima e transporte, que fica fora do filtro).
    pesados = Item.where('weight_kg > 60')
                  .where.not(category: %w[vehicle_land vehicle_water tack])
    if pesados.any?
      puts "  [aviso] #{pesados.count} item(ns) nao-transporte acima de 60 kg:"
      pesados.order(weight_kg: :desc).limit(15).each do |i|
        puts "    ##{i.id} #{i.name.inspect} (#{i.api_index}) #{i.weight_kg} kg"
      end
    end
  end
end
