# frozen_string_literal: true

# Funde os objetos do Inkarnate que entraram DUAS VEZES na biblioteca.
#
# Duas levas de importação anteriores (a conversão por MD5 do
# `inkarnate_objects.rake`, em 12-13/08, e um import posterior, em 25/08)
# gravaram o mesmo `ink-<assetId>.<ext>` em registros diferentes. O import do
# catálogo atual é idempotente por esse nome de arquivo e não cria duplicata —
# o que existe é herança, não vazamento novo. Resultado: o mesmo item aparece
# duas (às vezes três) vezes na biblioteca de objetos.
#
# ⚠️ "IMAGEM MAIOR" NÃO É `byte_size`. Medindo o cabeçalho dos 195 grupos cujos
# arquivos diferem, a RESOLUÇÃO é idêntica em todos: o que muda é só o quanto o
# PNG/WebP foi comprimido. Manter "o maior em bytes" escolheria a leva ANTIGA em
# metade dos casos — justo a que quase não tem objeto posicionado em mapa —
# forçando centenas de reapontamentos de token sem ganhar um pixel. Por isso o
# desempate começa por QUEM ESTÁ EM USO e só então olha resolução → bytes →
# mais recente. `PREFER=size` força o critério literal (resolução → bytes →
# recente, ignorando uso) para quem quiser comparar.
#
# ⚠️ NUNCA remove um objeto POSICIONADO num mapa sem antes reapontar o token. O
# vínculo é um número solto no jsonb, sem chave estrangeira — e o token guarda
# DUAS referências ao registro: `assetId` e a URL embutida em `customImageUrl`
# (`/api/v1/admin/map_assets/<id>/image?v=<blob>`). É a URL que o canvas
# desenha (useTokenImageCache), então trocar só o `assetId` deixaria o objeto
# invisível no mapa. As duas são reescritas, ou nada é removido.
#
# ⚠️ São DUAS tabelas com token, não uma: `battle_maps` e a vertente por mesa
# `schedule_battle_maps`. A poda (`objects_prune`) só olha a primeira; aqui as
# duas contam, tanto para preservar quanto para reapontar.
#
# ⚠️ NUNCA toca em arte PRÓPRIA do Mestre (categoria "Meus"): reusa a mesma
# lista da poda.
#
# Destrutivo: precisa de APPLY=1. Sem ele, só conta (DRY-RUN).
#
# Uso:
#   docker exec lafiga-web-1 bundle exec rails inkarnate:objects_dedupe
#   docker exec -e APPLY=1 lafiga-web-1 bundle exec rails inkarnate:objects_dedupe
namespace :inkarnate do
  # Onde um objeto posicionado guarda o id do MapAsset. Sem FK: é jsonb.
  TABELAS_COM_TOKEN = { 'battle_maps' => 'tokens', 'schedule_battle_maps' => 'tokens' }.freeze

  desc 'Funde MapAssets do Inkarnate repetidos (mesmo ink-<assetId>), reapontando tokens antes de remover. APPLY=1 executa.'
  task objects_dedupe: :environment do
    aplica = ENV['APPLY'] == '1'
    limit  = ENV['LIMIT'].to_i
    prefer = ENV['PREFER'].to_s

    conn = ActiveRecord::Base.connection

    # --- quem está posicionado, e onde -------------------------------------
    # refs[asset_id] = quantos tokens apontam para ele (nas DUAS tabelas)
    refs = Hash.new(0)
    TABELAS_COM_TOKEN.each do |tabela, coluna|
      conn.select_rows(<<~SQL).each { |id, n| refs[id.to_i] += n.to_i }
        SELECT t->>'assetId', count(*)
        FROM #{tabela} m, jsonb_array_elements(coalesce(m.#{coluna}, '[]'::jsonb)) t
        WHERE t->>'assetId' ~ '^[0-9]+$' AND (t->>'isObject')::boolean IS TRUE
        GROUP BY 1
      SQL
    end

    # --- os candidatos: objetos com arte do catálogo (ink-<aid>) ------------
    linhas = conn.select_all(<<~SQL).to_a
      SELECT ma.id, b.id AS blob_id, b.byte_size, b.checksum,
             substring(b.filename from 'ink-([0-9]+)\\.') AS aid
      FROM map_assets ma
      JOIN active_storage_attachments att
        ON att.record_id = ma.id AND att.record_type = 'MapAsset' AND att.name = 'image'
      JOIN active_storage_blobs b ON b.id = att.blob_id
      WHERE ma.kind = 'object'
        AND b.filename LIKE 'ink-%'
        AND ma.category NOT IN (#{CATEGORIAS_DO_MESTRE.map { |c| conn.quote(c) }.join(',')})
      ORDER BY ma.id
    SQL

    grupos = linhas.group_by { |r| r['aid'] }.select { |aid, v| aid.present? && v.size > 1 }
    grupos = grupos.first(limit).to_h if limit.positive?

    # --- "maior" de verdade: resolução lida do cabeçalho --------------------
    # Produção não converte imagem (sem libvips), e o analyzer do ActiveStorage
    # não gravou width/height no metadata — então a dimensão é lida do próprio
    # arquivo, 64 bytes de cada, sem baixar a imagem inteira.
    dimensoes = lambda do |blob_id|
      head = ActiveStorage::Blob.find(blob_id).download_chunk(0...64).to_s.b
      return head[16, 8].unpack('N2') if head.start_with?("\x89PNG\r\n\x1a\n".b)

      if head[0, 4] == 'RIFF'.b && head[8, 4] == 'WEBP'.b
        case head[12, 4]
        when 'VP8X'.b
          le24 = ->(s) { s.bytes.each_with_index.sum { |b, i| b << (8 * i) } + 1 }
          return [le24.call(head[24, 3]), le24.call(head[27, 3])]
        when 'VP8 '.b then return head[26, 4].unpack('v2').map { |x| x & 0x3fff }
        when 'VP8L'.b
          bits = head[21, 4].unpack1('V')
          return [(bits & 0x3fff) + 1, ((bits >> 14) & 0x3fff) + 1]
        end
      end
      nil
    rescue StandardError
      nil
    end

    px = Hash.new { |h, k| h[k] = dimensoes.call(k) }

    # Ranking. Maior primeiro. `uso` lidera porque token reapontado é escrita em
    # mapa de gente jogando; resolução idêntica não paga esse risco.
    ranking = lambda do |r|
      area = (d = px[r['blob_id']]) ? d[0].to_i * d[1].to_i : 0
      base = [area, r['byte_size'].to_i, r['id'].to_i]
      prefer == 'size' ? base : [refs[r['id'].to_i]] + base
    end

    counts = Hash.new(0)
    exemplos = []
    preservados = []

    grupos.each do |aid, membros|
      ordenados = membros.sort_by { |r| ranking.call(r) }.reverse
      vencedor = ordenados.first
      perdedores = ordenados.drop(1)
      counts[:grupos] += 1

      va = MapAsset.find_by(id: vencedor['id'])
      next counts[:vencedor_sumiu] += 1 unless va

      # --- fusão de metadado: o vencedor não pode REGREDIR -----------------
      # A leva nova nasceu sem `meta.shadow` em 151 grupos; a antiga tem. Se a
      # fusão não acontecer, deduplicar rebaixa a sombra desses objetos na
      # biblioteca — perda silenciosa, do tipo que só aparece no mapa.
      meta_novo = perdedores.reduce(va.meta || {}) do |acc, p|
        outro = MapAsset.find_by(id: p['id'])
        outro ? (outro.meta || {}).merge(acc) : acc
      end
      attrs = {}
      attrs[:meta] = meta_novo if meta_novo != (va.meta || {})
      if va.variant_group.to_s.strip.empty?
        doador = perdedores.map { |p| MapAsset.find_by(id: p['id']) }
                           .compact.find { |o| o.variant_group.to_s.strip.present? }
        if doador
          attrs[:variant_group] = doador.variant_group
          # `variant_order` só significa algo dentro de um grupo de variantes:
          # herda junto com ele, nunca sozinho.
          attrs[:variant_order] = doador.variant_order if va.variant_order.to_i.zero?
        end
      end
      if va.group_name.to_s.strip.empty?
        doador = perdedores.map { |p| MapAsset.find_by(id: p['id']) }
                           .compact.find { |o| o.group_name.to_s.strip.present? }
        attrs[:group_name] = doador.group_name if doador
      end
      if attrs.any?
        counts[:metadado_fundido] += 1
        va.update_columns(attrs.merge(updated_at: Time.current)) if aplica
      end

      url_nova = "/api/v1/admin/map_assets/#{va.id}/image?v=#{vencedor['blob_id']}"

      perdedores.each do |p|
        pid = p['id'].to_i
        usos = refs[pid]

        # --- reaponta ANTES de remover -----------------------------------
        if usos.positive?
          counts[:tokens_reapontados] += usos if aplica
          counts[:tokens_a_reapontar] += usos unless aplica
          reapontar_tokens(pid, va.id, url_nova) if aplica
        end

        # Blob compartilhado com outro registro: `destroy` purgaria o arquivo
        # de quem fica. Raro (o índice foi checado), mas o custo de errar é a
        # imagem sumir do vencedor.
        outros_anexos = conn.select_value(<<~SQL).to_i
          SELECT count(*) FROM active_storage_attachments
          WHERE blob_id = #{p['blob_id'].to_i} AND NOT (record_type = 'MapAsset' AND record_id = #{pid})
        SQL
        if outros_anexos.positive?
          counts[:blob_compartilhado_preservado] += 1
          preservados << "##{pid} (blob #{p['blob_id']} usado por outro anexo)"
          next
        end

        unless aplica
          counts[:removeria] += 1
          exemplos << [aid, vencedor['id'], pid, usos] if exemplos.size < 12
          next
        end

        # Cinto de segurança: relê o uso DEPOIS do reapontamento. Se sobrou
        # token apontando p/ este id, alguma escrita concorrente entrou no meio
        # — preserva e segue, nunca remove no escuro.
        if uso_atual(pid).positive?
          counts[:em_uso_preservado] += 1
          preservados << "##{pid} (ainda referenciado após reapontar)"
          next
        end

        registro = MapAsset.find_by(id: pid)
        next counts[:ja_removido] += 1 unless registro

        if registro.destroy
          counts[:removido] += 1
        else
          counts[:falhou] += 1
          warn "asset ##{pid}: #{registro.errors.full_messages.join(', ')}"
        end
      end
    end

    puts "== dedupe de objetos do Inkarnate #{aplica ? '' : '(DRY-RUN, sem APPLY=1) '}=="
    puts "   critério: #{prefer == 'size' ? 'PREFER=size (resolução → bytes → id)' : 'uso → resolução → bytes → id'}"
    puts "   #{counts.sort.to_h.inspect}"
    if exemplos.any?
      puts "== amostra (aid: mantém → remove):"
      exemplos.each { |aid, keep, drop, u| puts "   aid #{aid}: mantém ##{keep}, remove ##{drop}#{u.positive? ? " (#{u} tokens a reapontar)" : ''}" }
    end
    if preservados.any?
      puts "== preservados (#{preservados.size}):"
      preservados.first(40).each { |p| puts "   #{p}" }
      puts '   ...' if preservados.size > 40
    end
  end
end

# Reescreve, nas duas tabelas de token, as DUAS referências que o token guarda
# do asset removido: o `assetId` e a URL embutida em `customImageUrl` (é ela que
# o canvas desenha). Só toca no token cujo assetId é o antigo — qualquer outra
# imagem custom no mesmo mapa fica intacta.
def reapontar_tokens(id_antigo, id_novo, url_nova)
  TABELAS_COM_TOKEN.each do |tabela, coluna|
    conn = ActiveRecord::Base.connection
    ids = conn.select_values(<<~SQL)
      SELECT m.id FROM #{tabela} m
      WHERE EXISTS (
        SELECT 1 FROM jsonb_array_elements(coalesce(m.#{coluna}, '[]'::jsonb)) t
        WHERE t->>'assetId' = '#{id_antigo.to_i}'
      )
    SQL
    ids.each do |mid|
      atual = conn.select_value("SELECT #{coluna} FROM #{tabela} WHERE id = #{mid.to_i}")
      tokens = JSON.parse(atual.to_s.presence || '[]')
      novos = tokens.map do |t|
        next t unless t.is_a?(Hash) && t['assetId'].to_s == id_antigo.to_s

        t = t.merge('assetId' => id_novo)
        url = t['customImageUrl'].to_s
        t['customImageUrl'] = url_nova if url.include?("/map_assets/#{id_antigo}/image")
        t
      end
      conn.execute(<<~SQL)
        UPDATE #{tabela}
        SET #{coluna} = #{conn.quote(novos.to_json)}::jsonb, updated_at = NOW()
        WHERE id = #{mid.to_i}
      SQL
    end
  end
end

# Uso vivo de um asset, relido do banco (o cache do início do processo pode ter
# envelhecido enquanto a rake corre).
def uso_atual(asset_id)
  TABELAS_COM_TOKEN.sum do |tabela, coluna|
    ActiveRecord::Base.connection.select_value(<<~SQL).to_i
      SELECT count(*) FROM #{tabela} m, jsonb_array_elements(coalesce(m.#{coluna}, '[]'::jsonb)) t
      WHERE t->>'assetId' = '#{asset_id.to_i}'
    SQL
  end
end
