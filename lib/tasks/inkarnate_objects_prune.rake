# frozen_string_literal: true

# Remove os objetos que ficaram SEM arte em alta.
#
# Depois de `inkarnate:objects`, o que sobra em miniatura é o que não casa com
# nada no catálogo servido a esta conta (packs oficiais sci-fi e as variantes
# "BW", que a API não entrega). São itens de baixa resolução que só poluem a
# biblioteca.
#
# ⚠️ NUNCA toca em arte PRÓPRIA do Mestre (categoria "Meus"): ela não veio do
# catálogo, então não existe versão em alta p/ ela — "sem alta" ali não quer
# dizer descartável, quer dizer que é dele.
#
# ⚠️ NUNCA remove um objeto POSICIONADO num mapa. O token guarda só o `assetId`
# no jsonb de `battle_maps.tokens` — não há chave estrangeira, então apagar o
# asset deixaria o objeto no mapa apontando p/ imagem que não existe mais. Esses
# ficam e são listados no fim.
#
# Destrutivo: precisa de APPLY=1. Sem ele, só conta.
#
# Uso:
#   docker exec lafiga-web-1 bundle exec rails inkarnate:objects_prune
#   docker exec -e APPLY=1 lafiga-web-1 bundle exec rails inkarnate:objects_prune
namespace :inkarnate do
  # O que o Mestre enviou é dele: fora da poda, sempre.
  CATEGORIAS_DO_MESTRE = ['Meus'].freeze

  desc 'Remove objetos do catálogo sem arte em alta, preservando arte própria e os posicionados em mapas. APPLY=1 executa.'
  task objects_prune: :environment do
    aplica = ENV['APPLY'] == '1'
    limit  = ENV['LIMIT'].to_i

    # Ids de asset referenciados por algum objeto colocado num mapa.
    em_uso = ActiveRecord::Base.connection.select_values(<<~SQL).map(&:to_i).to_set
      SELECT DISTINCT (t->>'assetId')
      FROM battle_maps bm, jsonb_array_elements(coalesce(bm.tokens, '[]'::jsonb)) t
      WHERE t->>'assetId' IS NOT NULL AND (t->>'isObject')::boolean IS TRUE
    SQL

    alvos = MapAsset
            .joins(image_attachment: :blob)
            .where(kind: 'object')
            .where.not(category: CATEGORIAS_DO_MESTRE)
            .where.not('active_storage_blobs.filename LIKE ?', 'ink-%')
            .order(:id)
    alvos = alvos.limit(limit) if limit.positive?

    counts = Hash.new(0)
    preservados = []

    alvos.each do |ma|
      if em_uso.include?(ma.id)
        counts[:em_uso_preservado] += 1
        preservados << "##{ma.id} #{ma.name}"
        next
      end
      unless aplica
        counts[:removeria] += 1
        next
      end
      if ma.destroy
        counts[:removido] += 1
      else
        counts[:falhou] += 1
        warn "asset ##{ma.id}: #{ma.errors.full_messages.join(', ')}"
      end
    end

    puts "== poda de objetos #{aplica ? '' : '(SEM APPLY=1) '}== #{counts.sort.to_h.inspect}"
    if preservados.any?
      puts "== preservados por estarem em mapas (#{preservados.size}):"
      preservados.first(40).each { |p| puts "   #{p}" }
      puts '   ...' if preservados.size > 40
    end
  end
end
