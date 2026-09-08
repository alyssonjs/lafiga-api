# frozen_string_literal: true

# Importa as cenas do Inkarnate como BattleMaps EDITÁVEIS.
#
# O terreno entra como imagem de fundo (as camadas `brush` deles já vêm
# rasterizadas) e cada objeto vira um token de cenário apontando para o
# MapAsset do catálogo — parede rochosa, mobília, tudo continua editável.
#
# ⚠️ Os fundos são COMPOSTOS FORA daqui (`db/data/gerar_inkarnate_scenes.py`):
# produção não carrega libvips, então o rake só anexa o arquivo pronto. Aponte
# a pasta com os .webp por SCENES_DIR.
#
# Idempotência pelo NOME DO ARQUIVO do fundo (`ink-scene-<sid>.webp`), a mesma
# marca que o import do catálogo usa — dá para rodar em pedaços e retomar.
#
#   DRY_RUN=1 SCENES_DIR=/tmp/fundos rails inkarnate:scenes_import
#   OWNER_EMAIL=... SCENES_DIR=/tmp/fundos rails inkarnate:scenes_import
namespace :inkarnate do
  desc 'Importa cenas do Inkarnate como BattleMaps (fundo de terreno + objetos editáveis)'
  task scenes_import: :environment do
    dry = ENV['DRY_RUN'] == '1'
    limit = ENV['LIMIT'].to_i
    only = ENV['SID'].presence
    # SUBSTITUI=1 reimporta cena JÁ presente, atualizando o mapa NO LUGAR (o id
    # sobrevive, e com ele os vínculos de sessão). Recusa mapa que foi editado
    # depois de importado, salvo FORCE=1 — reimportar por cima do trabalho do
    # Mestre é destrutivo e silencioso.
    substitui = ENV['SUBSTITUI'] == '1'
    force = ENV['FORCE'] == '1'
    dir = ENV['SCENES_DIR'].presence || Rails.root.join('tmp/inkarnate_fundos').to_s

    arq = Rails.root.join('db/data/inkarnate_scenes.json')
    abort "índice não encontrado: #{arq}" unless File.exist?(arq)

    dono = if ENV['OWNER_EMAIL'].present?
             User.find_by(email: ENV['OWNER_EMAIL']) || abort("utilizador não encontrado: #{ENV['OWNER_EMAIL']}")
           else
             User.find_by(email: 'jmjulianomoreira@gmail.com') || User.order(:id).first
           end
    abort 'sem utilizador para ser dono dos mapas' unless dono

    indice = JSON.parse(File.read(arq))
    cenas = indice['cenas']
    cenas = cenas.select { |c| c['sid'].to_s == only } if only

    # Já importadas: o fundo anexado chama-se ink-scene-<sid>.webp
    presentes = ActiveRecord::Base.connection
                                  .select_values(
                                    ActiveRecord::Base.sanitize_sql_array(
                                      ['SELECT filename FROM active_storage_blobs WHERE filename LIKE ?', 'ink-scene-%'],
                                    ),
                                  )
                                  .filter_map { |f| f[/\Aink-scene-(\d+)\./, 1]&.to_i }
                                  .to_set

    faltantes = cenas.reject { |c| presentes.include?(c['sid']) }
    puts "== cenas #{indice['gerado_em']}: #{cenas.size} no índice, #{cenas.size - faltantes.size} já importadas"
    alvo = substitui ? cenas : faltantes
    pendentes = limit.positive? ? alvo.first(limit) : alvo
    puts "== a importar agora: #{pendentes.size} (dono: #{dono.email})"

    # aid do Inkarnate -> MapAsset, pelo mesmo nome de arquivo do import do catálogo.
    # ⚠️ Tudo de uma vez: são dezenas de milhares de tokens, e um find_by por
    # token dentro do laço seria N+1 com N na casa das dezenas de milhares.
    por_aid = {}
    ActiveStorage::Blob.joins(:attachments)
                       .where(active_storage_attachments: { record_type: 'MapAsset', name: 'image' })
                       .where('active_storage_blobs.filename LIKE ?', 'ink-%')
                       .pluck(:filename, 'active_storage_attachments.record_id', :id)
                       .each do |filename, record_id, blob_id|
      aid = filename[/\Aink-(\d+)\./, 1]&.to_i
      por_aid[aid] = { id: record_id, blob: blob_id } if aid
    end
    nomes = MapAsset.where(id: por_aid.values.map { |v| v[:id] }).pluck(:id, :name, :meta).to_h { |i, n, m| [i, [n, m]] }
    puts "== catálogo casável: #{por_aid.size} assets"

    # map_kind pelo estilo de cena: battlemap vira mesa, mundo/região não nascem
    # com grade (ver isWideAreaMapKind no front).
    tipo_por_estilo = {
      397 => 'battle', 364 => 'battle', 133 => 'battle',
      430 => 'city', 9 => 'world', 166 => 'world', 8 => 'region', 10 => 'region',
    }.freeze

    counts = Hash.new(0)
    pendentes.each do |c|
      sid = c['sid']
      largura = c['largura'].to_i
      altura = c['altura'].to_i
      caminho = c['fundo'] ? File.join(dir, c['fundo']) : nil

      if caminho && !File.exist?(caminho)
        counts[:sem_fundo_no_disco] += 1
        warn "#{sid} #{c['titulo']}: fundo ausente em #{caminho}"
        next
      end

      # Só entra token cujo asset existe na biblioteca: objeto sem arte é um
      # retângulo vazio no mapa.
      tokens = []
      c['tokens'].each_with_index do |t, i|
        ref = por_aid[t['aid']]
        nome_meta = ref && nomes[ref[:id]]
        if nome_meta.nil?
          counts[:token_sem_asset] += 1
          next
        end
        nome, meta = nome_meta

        tok = {
          'id' => "ink-#{sid}-#{i}",
          'name' => nome.to_s[0, 60],
          'color' => '#8a8a8a',
          'x' => t['x'], 'y' => t['y'],
          'size' => 1,
          'isObject' => true,
          'imageMode' => 'custom',
          # mesmo path que o serializer entrega ao front (o app grava assim)
          'customImageUrl' => "/api/v1/admin/map_assets/#{ref[:id]}/image?v=#{ref[:blob]}",
          'assetId' => ref[:id],
          'objectWidth' => t['w'], 'objectHeight' => t['h'],
        }
        tok['rotation'] = t['rot'] if t['rot']
        tok['sublayer'] = t['sub'] if t['sub']
        # Cor e mistura do stamp (o `ctx.filter`/`globalCompositeOperation` do
        # editor deles). Congelado no token pela mesma razao da sombra.
        tok['imageFx'] = t['ef'] if t['ef'].present?
        # Sombra POR STAMP, congelada no token igual ao carimbo do editor
        # (sessão e página pública não carregam a biblioteca).
        sombra = meta.is_a?(Hash) ? meta['shadow'] : nil
        if sombra == 'none'
          tok['shadowMode'] = 'none'
        elsif sombra.is_a?(Hash)
          u = c['celula_u'].to_f
          u = 200.0 unless u.positive?
          tok['shadowMode'] = 'custom'
          tok['shadowBlurCells'] = (sombra['b'].to_f / u).round(4)
          tok['shadowOffsetXCells'] = (sombra['x'].to_f / u).round(4)
          tok['shadowOffsetYCells'] = (sombra['y'].to_f / u).round(4)
          tok['shadowIntensity'] = sombra['i'].to_f
        end
        tokens << tok
      end

      # Mapa já importado desta cena: reconhecido pelo nome do anexo.
      existente = BattleMap.joins(background_image_attachment: :blob)
                           .find_by(active_storage_blobs: { filename: "ink-scene-#{sid}.webp" })
      if existente && !substitui
        counts[:ja_importado] += 1
        next
      end
      if existente && !force && existente.updated_at > existente.created_at + 5.minutes
        counts[:editado_preservado] += 1
        warn "#{c['titulo']}: mapa ##{existente.id} foi editado depois do import — use FORCE=1 para sobrescrever"
        next
      end

      if dry
        counts[existente ? :substituiria : :criaria] += 1
        puts "[dry] #{c['titulo']} #{largura}x#{altura} — #{tokens.size} objetos" \
             "#{existente ? " [substitui ##{existente.id}]" : ''}"
        next
      end

      mapa = existente || BattleMap.new(user: dono)
      # SUBSTITUI num mapa vivo FUNDE em vez de zerar: so os tokens do import
      # (id "ink-<sid>-*") sao repostos; criaturas e cenario colocados a mao
      # ficam (por cima), e o terreno pintado (cells) sobrevive quando as
      # dimensoes nao mudaram. Zera-los apagaria trabalho do Mestre.
      if existente
        de_fora = existente.tokens.reject { |t| t['id'].to_s.start_with?("ink-#{sid}-") }
        tokens += de_fora
      end
      celulas = if existente && existente.width == largura && existente.height == altura
                  existente.cells
                else
                  Array.new(altura) { Array.new(largura, 'empty') }
                end
      mapa.assign_attributes(
        name: c['titulo'],
        width: largura,
        height: altura,
        cells: celulas,
        tokens: tokens,
        map_kind: tipo_por_estilo[c['estilo']] || 'battle',
      )
      if c['fundo_px'].is_a?(Array)
        mapa.background_image_pixel_width = c['fundo_px'][0]
        mapa.background_image_pixel_height = c['fundo_px'][1]
      end
      if caminho
        antigo = mapa.background_image.attached? ? mapa.background_image.blob : nil
        mapa.background_image.attach(
          io: File.open(caminho),
          filename: "ink-scene-#{sid}.webp",
          content_type: 'image/webp',
        )
      end
      # Miniatura do card da lista: gerada no gerador a partir do fundo, senão
      # ela só nasceria quando o construtor capturasse a tela — e sairia com a
      # textura chapada se o fundo ainda não tivesse carregado.
      caminho_thumb = File.join(dir, "#{sid}-thumb.webp")
      if File.exist?(caminho_thumb)
        b64 = Base64.strict_encode64(File.binread(caminho_thumb))
        mapa.background_thumbnail = "data:image/webp;base64,#{b64}"
      end
      # Silhueta de terra (alfa = terra): semeia a Ferramenta de Terra — o
      # litoral fica vivo/editável e pintar/apagar opera na união. Só existe
      # para cena cuja máscara distingue terra de mar (o gerador decide).
      caminho_mascara = File.join(dir, "#{sid}-mask.webp")
      mascara_antiga = nil
      if File.exist?(caminho_mascara)
        mascara_antiga = mapa.land_mask.attached? ? mapa.land_mask.blob : nil
        mapa.land_mask.attach(
          io: File.open(caminho_mascara),
          filename: "ink-scene-mask-#{sid}.webp",
          content_type: 'image/webp',
        )
      end

      if mapa.save
        # ⚠️ purge SÍNCRONO do fundo anterior: a fila em processo morre com o
        # Puma (mesma razão do import do catálogo).
        antigo&.purge
        mascara_antiga&.purge
        counts[existente ? :substituido : :criado] += 1
        puts "   ##{mapa.id} #{c['titulo']} — #{largura}x#{altura}, #{tokens.size} objetos"
      else
        counts[:invalido] += 1
        warn "#{c['titulo']}: #{mapa.errors.full_messages.join(', ')}"
      end
    end

    puts "== importação de cenas #{dry ? '(DRY RUN) ' : ''}== #{counts.sort.to_h.inspect}"
  end
end
