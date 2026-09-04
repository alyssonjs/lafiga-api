# frozen_string_literal: true

# Objetos do Map Builder: troca a MINIATURA de 160px pela arte em alta e
# reorganiza categoria/subcategoria/variantes com os metadados do Inkarnate.
#
# Motivação: os ~1.9k `MapAsset kind='object'` entraram por importação em lote
# a partir das miniaturas do catálogo — imagem pequena e nomes de sequência
# ("cities 314", "Arvores 41") num punhado de categorias genéricas.
#
# O índice `db/data/inkarnate_objects.json` foi gerado fora daqui (ver
# `db/data/gerar_inkarnate_objects.py`): cada item casa um MapAsset com o asset
# do catálogo por MD5 da miniatura ou por semelhança visual, e traz o CHECKSUM
# atual do blob. Se o blob em produção não for o que foi casado, o item é
# pulado — nada é aplicado no escuro.
#
# Só entram no índice packs oficiais (assinatura Pro): arte de pack pago não
# comprado não é baixada — desses assets vem apenas o metadado que organiza.
#
# Idempotente: o arquivo anexado passa a se chamar `ink-<assetId>.<ext>`; numa
# segunda passada o item já convertido pula o download (o metadado é reaplicado,
# o que é inofensivo).
#
# Uso:
#   docker exec -e DRY_RUN=1 lafiga_api bundle exec rails inkarnate:objects
#   docker exec -e LIMIT=20 lafiga_api bundle exec rails inkarnate:objects
#   docker exec -e ONLY=meta lafiga_api bundle exec rails inkarnate:objects
namespace :inkarnate do
  desc 'Objetos: imagem em alta + categoria/variantes do catálogo. DRY_RUN=1 simula, LIMIT=n corta, ONLY=meta|image restringe.'
  task objects: :environment do
    require 'open-uri'
    require 'json'

    dry   = ENV['DRY_RUN'] == '1'
    limit = ENV['LIMIT'].to_i
    only  = ENV['ONLY'].presence
    arq   = Rails.root.join('db/data/inkarnate_objects.json')

    unless File.exist?(arq)
      abort "índice não encontrado: #{arq}"
    end

    indice = JSON.parse(File.read(arq))
    itens  = indice['itens']
    itens  = itens.first(limit) if limit.positive?
    puts "== índice #{indice['gerado_em']} — #{itens.size} de #{indice['total']} itens (alvo #{indice['alvo_px']}px)"

    counts = Hash.new(0)
    bytes  = 0

    itens.each do |it|
      ma = MapAsset.find_by(id: it['id'])
      if ma.nil?
        counts[:sumiu] += 1
        next
      end
      unless ma.kind == 'object'
        counts[:nao_e_objeto] += 1
        next
      end

      nome_ink = "ink-#{it['aid']}"
      ja_alta  = ma.image.attached? && ma.image.filename.to_s.start_with?("#{nome_ink}.")

      # Trava de identidade: sem a arte em alta ainda, o blob tem que ser
      # exatamente aquele que o casamento viu.
      if !ja_alta && it['chk'].present? && ma.image.attached? && ma.image.blob.checksum != it['chk']
        counts[:divergente] += 1
        warn "asset ##{ma.id} '#{ma.name}': blob diferente do casado (pulado)"
        next
      end

      # --- metadados (categoria/subcategoria/variantes) ---
      if only != 'image' && it['c'].present?
        patch = {
          name: it['n'].presence || ma.name,
          category: it['c'],
          group_name: it['g'],
          variant_group: it['vg'],
          variant_order: it['vo'].to_i,
        }
        mudou = patch.any? { |k, v| ma.public_send(k) != v }
        if mudou
          if dry
            counts[:meta_mudaria] += 1
            puts "[dry] ##{ma.id} '#{ma.name}' → #{patch[:name]} [#{patch[:category]}/#{patch[:group_name]}] vg=#{patch[:variant_group]} ord=#{patch[:variant_order]}"
          else
            ma.assign_attributes(patch)
            if ma.save
              counts[:meta_atualizado] += 1
            else
              counts[:meta_invalido] += 1
              warn "asset ##{ma.id}: #{ma.errors.full_messages.join(', ')}"
            end
          end
        else
          counts[:meta_igual] += 1
        end
      end

      # --- imagem em alta ---
      next if only == 'meta'
      urls = Array(it['us'])
      if urls.empty?
        counts[:sem_imagem] += 1
        next
      end
      if ja_alta
        counts[:imagem_ja_alta] += 1
        next
      end
      if dry
        counts[:imagem_baixaria] += 1
        next
      end

      dados = nil
      tipo  = nil
      urls.each do |u|
        begin
          io = URI.parse(u).open(
            'Accept' => 'image/webp,image/png,image/*',
            'User-Agent' => 'lafiga/1.0',
            read_timeout: 60,
          )
        rescue StandardError => e
          warn "asset ##{ma.id}: falha em #{u} (#{e.class})"
          next
        end
        bruto = io.read
        ct    = (io.respond_to?(:content_type) ? io.content_type : nil).to_s
        ct    = 'image/png' unless MapAsset::ALLOWED_CONTENT_TYPES.include?(ct)
        # teto do model: se estourou, tenta a variante menor
        next if bruto.bytesize > MapAsset::MAX_BYTES

        dados = bruto
        tipo  = ct
        break
      end

      if dados.nil?
        counts[:imagem_falhou] += 1
        warn "asset ##{ma.id} '#{ma.name}': nenhuma variante coube (pulado)"
        next
      end

      ext = tipo.split('/').last.sub('jpeg', 'jpg')
      ma.image.attach(io: StringIO.new(dados), filename: "#{nome_ink}.#{ext}", content_type: tipo)
      if ma.save
        counts[:imagem_trocada] += 1
        bytes += dados.bytesize
      else
        counts[:imagem_invalida] += 1
        warn "asset ##{ma.id}: #{ma.errors.full_messages.join(', ')}"
      end
    end

    puts "== objetos Inkarnate #{dry ? '(DRY RUN) ' : ''}== #{counts.sort.to_h.inspect}"
    puts "== baixados #{(bytes / 1_048_576.0).round(1)} MB" if bytes.positive?
  end
end
