# frozen_string_literal: true

# Biblioteca de TEXTURAS de terreno: nasce em produção a partir do índice
# `db/data/inkarnate_textures.json`.
#
# Produção não tem nenhuma textura no banco — o que o pincel usa por padrão
# (`tx-grass`, `tx-water`) são constantes do FRONT, não registros. A biblioteca
# que o Mestre vê existia só no banco de desenvolvimento.
#
# O índice guarda, por textura, a URL do CDN de onde a imagem veio (casada por
# MD5 do blob local): produção recebe exatamente o arquivo testado em dev. Vai
# a versão em ALTA de cada terreno; a miniatura só sobrevive quando não existe
# HD equivalente.
#
# Idempotente por (kind, category, name): rodar de novo não duplica.
#
# Uso:
#   docker exec -e DRY_RUN=1 lafiga_api bundle exec rails inkarnate:textures
#   docker exec -e LIMIT=10 lafiga_api bundle exec rails inkarnate:textures
namespace :inkarnate do
  desc 'Cria a biblioteca de texturas de terreno a partir do catálogo. DRY_RUN=1 simula, LIMIT=n corta.'
  task textures: :environment do
    require 'open-uri'
    require 'json'

    dry   = ENV['DRY_RUN'] == '1'
    limit = ENV['LIMIT'].to_i
    arq   = Rails.root.join('db/data/inkarnate_textures.json')
    abort "índice não encontrado: #{arq}" unless File.exist?(arq)

    indice   = JSON.parse(File.read(arq))
    categoria = indice['categoria'].presence || 'Terrenos'
    itens    = indice['itens']
    itens    = itens.first(limit) if limit.positive?
    puts "== índice #{indice['gerado_em']} — #{itens.size} de #{indice['total']} texturas → categoria '#{categoria}'"

    counts = Hash.new(0)
    bytes  = 0

    itens.each do |it|
      nome = it['n'].to_s.strip
      if nome.empty?
        counts[:sem_nome] += 1
        next
      end

      if MapAsset.exists?(kind: 'texture', category: categoria, name: nome)
        counts[:ja_existe] += 1
        next
      end

      if dry
        counts[:criaria] += 1
        puts "[dry] '#{nome}' [#{categoria}/#{it['g']}] ord=#{it['vo']}"
        next
      end

      begin
        io = URI.parse(it['u']).open('User-Agent' => 'lafiga/1.0', read_timeout: 90)
      rescue StandardError => e
        counts[:download_falhou] += 1
        warn "'#{nome}': #{e.class} em #{it['u']}"
        next
      end

      dados = io.read
      tipo  = it['ct'].to_s
      tipo  = (io.respond_to?(:content_type) ? io.content_type.to_s : '') unless MapAsset::ALLOWED_CONTENT_TYPES.include?(tipo)
      unless MapAsset::ALLOWED_CONTENT_TYPES.include?(tipo)
        counts[:tipo_invalido] += 1
        next
      end
      if dados.bytesize > MapAsset::MAX_BYTES
        counts[:grande_demais] += 1
        warn "'#{nome}': #{(dados.bytesize / 1024.0).round}KB acima do teto"
        next
      end

      ext = tipo.split('/').last.sub('jpeg', 'jpg')
      asset = MapAsset.new(
        name: nome,
        kind: 'texture',
        category: categoria,
        group_name: it['g'],
        variant_group: it['vg'],
        variant_order: it['vo'].to_i,
        enabled: true,
      )
      asset.image.attach(io: StringIO.new(dados), filename: "inktex-#{nome.parameterize}.#{ext}", content_type: tipo)
      if asset.save
        counts[:criada] += 1
        bytes += dados.bytesize
      else
        counts[:invalida] += 1
        warn "'#{nome}': #{asset.errors.full_messages.join(', ')}"
      end
    end

    puts "== texturas Inkarnate #{dry ? '(DRY RUN) ' : ''}== #{counts.sort.to_h.inspect}"
    puts "== baixados #{(bytes / 1_048_576.0).round(1)} MB" if bytes.positive?
  end
end
