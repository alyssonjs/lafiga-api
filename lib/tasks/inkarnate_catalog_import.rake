# frozen_string_literal: true

# Importa o CATÁLOGO INTEIRO (objetos, texturas ou caminhos) que a conta acessa.
#
# ⚠️ CAMINHO não tem imagem própria no Inkarnate: é uma receita que aponta p/ o
# stamp que se repete ao longo da linha. O índice já resolve isso e guarda a URL
# do TILE — ver `db/data/gerar_inkarnate_paths_catalog.py`.
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
#   docker exec -e KIND=texture lafiga-web-1 bundle exec rails inkarnate:catalog_import
#   docker exec -e UPGRADE=1 -e KIND=texture lafiga-web-1 bundle exec rails inkarnate:catalog_import
#
# UPGRADE=1 inverte a mira: só os JÁ presentes, baixando de novo e trocando o
# anexo quando a imagem nova é MAIOR (largura; bytes quando a largura não dá).
# ⚠️ Mantém o mesmo `map_asset.id` — os mapas referenciam `up-<id>` e o
# `?v=` da URL é o id do blob, então a troca invalida o cache sozinha.
namespace :inkarnate do
  desc 'Importa o catálogo do Inkarnate. KIND=object|texture|path; DRY_RUN=1 simula; LIMIT/STYLE/PACK recortam; UPGRADE=1 troca por imagem maior.'
  task catalog_import: :environment do
    require 'open-uri'
    require 'json'
    # ⚠️ o Rails só carrega o MiniMagick quando o analisador do Active Storage
    # roda; sem este require a 1ª medição de largura morre num NameError que o
    # `rescue nil` engole — e o UPGRADE compara por bytes sem avisar.
    require 'mini_magick'

    dry   = ENV['DRY_RUN'] == '1'
    limit = ENV['LIMIT'].to_i
    style = ENV['STYLE'].presence
    pack  = ENV['PACK'].presence
    kind  = ENV['KIND'].presence || 'object'
    upgrade = ENV['UPGRADE'] == '1'
    abort "KIND inválido: #{kind}" unless %w[object texture path].include?(kind)
    # ⚠️ Prefixos diferentes E que não se confundem no LIKE: 'inktex-...' não
    # casa com 'ink-%', então a poda de objetos nunca mira uma textura.
    prefixo = { 'texture' => 'inktex', 'path' => 'inkpath' }.fetch(kind, 'ink')
    arq = Rails.root.join({
      'texture' => 'db/data/inkarnate_textures_catalog.json',
      'path' => 'db/data/inkarnate_paths_catalog.json',
    }.fetch(kind, 'db/data/inkarnate_catalog.json'))
    abort "índice não encontrado: #{arq}" unless File.exist?(arq)

    indice = JSON.parse(File.read(arq))
    itens  = indice['itens']
    itens  = itens.select { |i| i['c'] == style } if style
    itens  = itens.select { |i| i['g'] == pack } if pack

    # Já presentes: qualquer MapAsset cuja imagem é `ink-<assetId>.*`.
    presentes = ActiveRecord::Base.connection
                                  .select_values(
                                    ActiveRecord::Base.sanitize_sql_array(
                                      ['SELECT filename FROM active_storage_blobs WHERE filename LIKE ?', "#{prefixo}-%"],
                                    ),
                                  )
                                  .filter_map { |f| f[/\A#{prefixo}-(\d+)\./, 1]&.to_i }
                                  .to_set

    faltantes = itens.reject { |i| presentes.include?(i['aid']) }
    # ⚠️ o "já presentes" tem que sair ANTES do LIMIT, senão o corte do limite
    # se disfarça de item importado.
    puts "== catálogo #{indice['gerado_em']}: #{itens.size} itens, #{itens.size - faltantes.size} já presentes"
    # UPGRADE mira o complemento: quem JÁ está na biblioteca. O aid vem do nome
    # do arquivo, o registro (id + tamanho atual) da junção com o anexo.
    atuais = {}
    # UPGRADE troca imagem; META=1 regrava metadados — os dois precisam do
    # mapa aid→registro dos já presentes.
    if upgrade || ENV['META'] == '1'
      ActiveStorage::Blob.joins(:attachments)
                         .where(active_storage_attachments: { record_type: 'MapAsset', name: 'image' })
                         .where('active_storage_blobs.filename LIKE ?', "#{prefixo}-%")
                         .pluck(:filename, 'active_storage_attachments.record_id', :byte_size, :metadata)
                         .each do |filename, record_id, byte_size, metadata|
        aid = filename[/\A#{prefixo}-(\d+)\./, 1]&.to_i
        next unless aid

        metadata = JSON.parse(metadata) rescue {} if metadata.is_a?(String)
        atuais[aid] = { id: record_id, bytes: byte_size.to_i, width: metadata&.dig('width') }
      end
    end
    alvo = upgrade ? itens.select { |i| atuais.key?(i['aid']) } : faltantes
    pendentes = limit.positive? ? alvo.first(limit) : alvo
    puts "== a #{upgrade ? 'verificar (UPGRADE)' : 'importar'} agora: #{pendentes.size}#{limit.positive? ? " (LIMIT=#{limit} de #{alvo.size})" : ''}"

    # META=1: SÓ regrava o meta dos já presentes a partir do catálogo — sem
    # baixar nada. É o backfill de prod depois que o catálogo ganhou a sombra.
    if ENV['META'] == '1'
      c = Hash.new(0)
      itens.each do |it|
        atual = atuais[it['aid']]
        next unless atual
        meta = meta_de.call(it)
        asset = MapAsset.find_by(id: atual[:id])
        next c[:sumiu] += 1 unless asset
        if asset.meta == meta
          c[:igual] += 1
        elsif dry
          c[:regravaria] += 1
        else
          asset.update_columns(meta: meta)
          c[:regravado] += 1
        end
      end
      puts "== backfill de meta (#{kind}) #{dry ? '(DRY RUN) ' : ''}== #{c.sort.to_h.inspect}"
      next
    end

    counts = Hash.new(0)
    bytes  = 0

    # Baixa a 1ª URL que cabe no teto do model; [dados, content_type] ou nil.
    baixar = lambda do |it|
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

        return [bruto, ct]
      end
      nil
    end
    largura = ->(bin) { MiniMagick::Image.read(bin)[:width] rescue nil }
    # Sombra do catálogo → meta['shadow'] ('none' | {b,x,y,i} em unidades de
    # cena, 200/célula). Ausente no item = padrão do estilo = meta sem a chave.
    meta_de = ->(it) { it['sh'] ? { 'shadow' => it['sh'] } : {} }

    pendentes.each_with_index do |it, i|
      if dry
        counts[upgrade ? :verificaria : :criaria] += 1
        puts "[dry] #{it['n']} [#{it['c']}/#{it['g']}] vg=#{it['vg']} ord=#{it['vo']}#{upgrade ? " up-#{atuais[it['aid']][:id]} (#{atuais[it['aid']][:bytes]} B)" : ''}" if i < 10
        next
      end

      dados, tipo = baixar.call(it)
      if dados.nil?
        counts[:sem_imagem] += 1
        next
      end

      ext = tipo.split('/').last.sub('jpeg', 'jpg')

      if upgrade
        atual = atuais[it['aid']]
        asset = MapAsset.with_attached_image.find_by(id: atual[:id])
        if asset.nil? || !asset.image.attached?
          counts[:falha] += 1
          warn "#{it['n']}: up-#{atual[:id]} sumiu entre a listagem e a troca"
          next
        end

        # Largura decide quando as duas são conhecidas (JPEG maior pode pesar
        # MENOS que um PNG menor); bytes é o recuo quando o blob antigo nunca
        # foi analisado ou a imagem nova não abre.
        nova_w  = largura.call(dados)
        atual_w = atual[:width] || (largura.call(asset.image.download) rescue nil)
        maior = if nova_w && atual_w
                  nova_w > atual_w
                else
                  dados.bytesize > atual[:bytes]
                end
        unless maior
          counts[:pulado_nao_maior] += 1
          next
        end

        antigo = asset.image.blob
        asset.meta = meta_de.call(it)
        asset.image.attach(io: StringIO.new(dados), filename: "#{prefixo}-#{it['aid']}.#{ext}", content_type: tipo)
        if asset.save
          # ⚠️ purge SÍNCRONO do blob anterior: o Rails só enfileira `purge_later`
          # ao destruir o anexo velho, e a fila em processo morre com o Puma.
          # O PurgeJob descarta RecordNotFound, então as duas vias convivem.
          antigo.purge
          # grava width/height agora, p/ o próximo UPGRADE comparar por largura
          asset.image.blob.analyze
          counts[:atualizado] += 1
          bytes += dados.bytesize
          puts "   up-#{asset.id} #{it['n']}: #{atual_w || '?'}px/#{atual[:bytes]} B → #{nova_w || '?'}px/#{dados.bytesize} B"
        else
          counts[:falha] += 1
          warn "#{it['n']}: #{asset.errors.full_messages.join(', ')}"
        end
        next
      end

      asset = MapAsset.new(
        name: it['n'],
        kind: kind,
        category: it['c'],
        group_name: it['g'],
        variant_group: it['vg'],
        variant_order: it['vo'].to_i,
        enabled: true,
        meta: meta_de.call(it),
      )
      asset.image.attach(io: StringIO.new(dados), filename: "#{prefixo}-#{it['aid']}.#{ext}", content_type: tipo)
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
    puts "== importação do catálogo (#{kind}) #{dry ? '(DRY RUN) ' : ''}== #{counts.sort.to_h.inspect}"
    puts "== baixados #{(bytes / 1_048_576.0).round(1)} MB" if bytes.positive?
  end
end
