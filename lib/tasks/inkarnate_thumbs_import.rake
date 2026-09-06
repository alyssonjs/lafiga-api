# frozen_string_literal: true

# Anexa a MINIATURA da biblioteca a cada MapAsset do catálogo.
#
# A grelha de itens mostra o objeto num quadrado de ~100 px, mas não havia
# miniatura nenhuma: cada card baixava e descodificava a ARTE (medido em prod:
# 254 KB, ~300 px por card; uma busca de 400 cards = 68 MB). Era a "performance
# de renderização baixa" da biblioteca.
#
# ⚠️ As miniaturas NÃO nascem aqui: prod não tem ImageMagick/vips (nem há CDN
# com resize à frente), então converter no servidor é impossível. Elas vêm
# prontas de `db/db/data/gerar_inkarnate_thumbs.py` (webp ~160 px) e chegam por
# scp+docker cp — o mesmo contrato dos fundos de cena. Aponte a pasta com
# THUMBS_DIR.
#
# Casamento pelo NOME DO FICHEIRO, a mesma chave de todo o pipeline do catálogo:
# a imagem do asset chama-se `<pref>-<aid>.<ext>` e a miniatura `<pref>-<aid>.webp`.
#
# Idempotente: quem já tem `thumb` anexado é pulado (REPOR=1 troca).
#
# Uso:
#   docker exec -e DRY_RUN=1 -e THUMBS_DIR=/tmp/thumbs lafiga-web-1 \
#     bundle exec rails inkarnate:thumbs_import
#   docker exec -e THUMBS_DIR=/tmp/thumbs lafiga-web-1 \
#     bundle exec rails inkarnate:thumbs_import
namespace :inkarnate do
  desc 'Anexa miniaturas (webp) da biblioteca. THUMBS_DIR=pasta; DRY_RUN=1 simula; LIMIT=n; REPOR=1 troca as existentes.'
  task thumbs_import: :environment do
    dir = ENV['THUMBS_DIR'].presence || Rails.root.join('tmp/ink_thumbs').to_s
    abort "pasta não encontrada: #{dir}" unless File.directory?(dir)

    dry   = ENV['DRY_RUN'] == '1'
    limit = ENV['LIMIT'].to_i
    repor = ENV['REPOR'] == '1'

    # No disco: `<pref>-<aid>.webp` → caminho.
    no_disco = Dir.glob(File.join(dir, '*.webp')).each_with_object({}) do |caminho, h|
      h[File.basename(caminho, '.webp')] = caminho
    end
    puts "== miniaturas no disco: #{no_disco.size}"

    # ⚠️ A CHAVE do asset vem do nome do ficheiro da IMAGEM (ink-123.png →
    # 'ink-123'), não do id do registo: é assim que todo o pipeline do catálogo
    # casa, e sobrevive a reimportações que trocam o id do blob.
    chave_por_asset = {}
    ActiveStorage::Blob
      .joins(:attachments)
      .where(active_storage_attachments: { record_type: 'MapAsset', name: 'image' })
      .pluck('active_storage_attachments.record_id', :filename)
      .each do |record_id, filename|
        chave = File.basename(filename.to_s, File.extname(filename.to_s))
        chave_por_asset[record_id] = chave
      end

    # Quem JÁ tem miniatura — para pular sem tocar no disco.
    com_thumb = ActiveStorage::Attachment
                .where(record_type: 'MapAsset', name: 'thumb')
                .pluck(:record_id)
                .to_set

    alvos = chave_por_asset.select do |record_id, chave|
      no_disco.key?(chave) && (repor || !com_thumb.include?(record_id))
    end
    pendentes = limit.positive? ? alvos.first(limit).to_h : alvos

    puts "== assets com imagem: #{chave_por_asset.size}; já com miniatura: #{com_thumb.size}"
    puts "== a anexar agora: #{pendentes.size}#{limit.positive? ? " (LIMIT=#{limit} de #{alvos.size})" : ''}"
    sem_arquivo = chave_por_asset.size - chave_por_asset.count { |_id, c| no_disco.key?(c) }
    puts "== sem miniatura no disco (ficam na imagem cheia): #{sem_arquivo}" if sem_arquivo.positive?

    if dry
      pendentes.first(5).each { |id, chave| puts "[dry] asset #{id} ← #{chave}.webp" }
      puts "== (DRY RUN) anexaria #{pendentes.size}"
      next
    end

    counts = Hash.new(0)
    bytes = 0
    pendentes.each_slice(200) do |fatia|
      MapAsset.with_attached_thumb.where(id: fatia.map(&:first)).find_each do |asset|
        chave = chave_por_asset[asset.id]
        caminho = no_disco[chave]
        next counts[:sem_arquivo] += 1 unless caminho

        dados = File.binread(caminho)
        antigo = repor && asset.thumb.attached? ? asset.thumb.blob : nil
        asset.thumb.attach(
          io: StringIO.new(dados),
          filename: "#{chave}.webp",
          content_type: 'image/webp',
        )
        # ⚠️ purge SÍNCRONO do anterior: a fila em processo morre com o Puma
        # (mesma razão do catalog_import).
        antigo&.purge
        counts[:anexado] += 1
        bytes += dados.bytesize
      end
      puts "   … #{counts[:anexado]} anexadas (#{(bytes / 1_048_576.0).round} MB)"
    end

    puts "== miniaturas #{counts.sort.to_h.inspect}; #{(bytes / 1_048_576.0).round(1)} MB"
  end
end
