# frozen_string_literal: true

# Importa o CATÁLOGO INTEIRO de objetos que a conta acessa.
#
# A conversão em alta (`inkarnate:objects`) só melhorava o que já tínhamos
# importado à mão: 2.783 registros, ~18% do catálogo. O que faltava na
# biblioteca não era qualidade, eram os ITENS — "Core" de Fantasy Battlemaps
# tem 353 assets no catálogo e a nossa tinha 24, e packs inteiros (Artisans,
# Castle, Elves, Farm...) nunca chegaram.
#
# Cada item nasce com o metadado que organiza a biblioteca: estilo de cena vira
# categoria, pack vira subcategoria, e o grupo do catálogo agrega as variantes.
#
# Idempotente pelo NOME DO ARQUIVO anexado (`ink-<assetId>.<ext>`): o que já foi
# convertido ou importado é pulado, então dá p/ rodar em pedaços e retomar.
#
# Uso:
#   docker exec -e DRY_RUN=1 lafiga-web-1 bundle exec rails inkarnate:catalog_import
#   docker exec -e LIMIT=200 lafiga-web-1 bundle exec rails inkarnate:catalog_import
#   docker exec -e STYLE='Fantasy Battlemaps' lafiga-web-1 bundle exec rails inkarnate:catalog_import
namespace :inkarnate do
  desc 'Importa o catálogo de objetos do Inkarnate. DRY_RUN=1 simula; LIMIT/STYLE/PACK recortam.'
  task catalog_import: :environment do
    require 'open-uri'
    require 'json'

    dry   = ENV['DRY_RUN'] == '1'
    limit = ENV['LIMIT'].to_i
    style = ENV['STYLE'].presence
    pack  = ENV['PACK'].presence
    arq   = Rails.root.join('db/data/inkarnate_catalog.json')
    abort "índice não encontrado: #{arq}" unless File.exist?(arq)

    indice = JSON.parse(File.read(arq))
    itens  = indice['itens']
    itens  = itens.select { |i| i['c'] == style } if style
    itens  = itens.select { |i| i['g'] == pack } if pack

    # Já presentes: qualquer MapAsset cuja imagem é `ink-<assetId>.*`.
    presentes = ActiveRecord::Base.connection
                                  .select_values("SELECT filename FROM active_storage_blobs WHERE filename LIKE 'ink-%'")
                                  .filter_map { |f| f[/\Aink-(\d+)\./, 1]&.to_i }
                                  .to_set

    pendentes = itens.reject { |i| presentes.include?(i['aid']) }
    pendentes = pendentes.first(limit) if limit.positive?
    puts "== catálogo #{indice['gerado_em']}: #{itens.size} itens, #{itens.size - pendentes.size} já presentes"
    puts "== a importar agora: #{pendentes.size}"

    counts = Hash.new(0)
    bytes  = 0

    pendentes.each_with_index do |it, i|
      if dry
        counts[:criaria] += 1
        puts "[dry] #{it['n']} [#{it['c']}/#{it['g']}] vg=#{it['vg']} ord=#{it['vo']}" if i < 10
        next
      end

      dados = nil
      tipo  = nil
      Array(it['us']).each do |u|
        begin
          io = URI.parse(u).open(
            'Accept' => 'image/webp,image/png,image/*',
            'User-Agent' => 'lafiga/1.0',
            read_timeout: 60,
          )
        rescue StandardError => e
          warn "#{it['n']}: #{e.class} em #{u}"
          next
        end
        bruto = io.read
        ct    = (io.respond_to?(:content_type) ? io.content_type : nil).to_s
        ct    = 'image/png' unless MapAsset::ALLOWED_CONTENT_TYPES.include?(ct)
        next if bruto.bytesize > MapAsset::MAX_BYTES

        dados = bruto
        tipo  = ct
        break
      end

      if dados.nil?
        counts[:sem_imagem] += 1
        next
      end

      ext = tipo.split('/').last.sub('jpeg', 'jpg')
      asset = MapAsset.new(
        name: it['n'],
        kind: 'object',
        category: it['c'],
        group_name: it['g'],
        variant_group: it['vg'],
        variant_order: it['vo'].to_i,
        enabled: true,
      )
      asset.image.attach(io: StringIO.new(dados), filename: "ink-#{it['aid']}.#{ext}", content_type: tipo)
      if asset.save
        counts[:criado] += 1
        bytes += dados.bytesize
      else
        counts[:invalido] += 1
        warn "#{it['n']}: #{asset.errors.full_messages.join(', ')}"
      end

      if (counts[:criado] % 200).zero? && counts[:criado].positive? && (counts[:criado] != counts[:ultimo_log])
        counts[:ultimo_log] = counts[:criado]
        puts "   ... #{counts[:criado]} criados (#{(bytes / 1_048_576.0).round} MB)"
      end
    end

    counts.delete(:ultimo_log)
    puts "== importação do catálogo #{dry ? '(DRY RUN) ' : ''}== #{counts.sort.to_h.inspect}"
    puts "== baixados #{(bytes / 1_048_576.0).round(1)} MB" if bytes.positive?
  end
end
