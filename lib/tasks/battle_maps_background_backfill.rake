# frozen_string_literal: true

# Backfill: migra o fundo dos mapas de base64 inline (coluna text
# `background_image_url`) → Active Storage blob (`background_image`).
#
# Motivação: o base64 inline (dezenas de MB p/ mapas 8k) inflava o payload :full
# → serialização de até 40s por GET /battle_maps/:id (e o MapList disparava um por
# card). Com o blob, o :full manda só uma URL curta e o fundo é servido/cacheado
# à parte.
#
# Idempotente: pula mapas que já têm o blob anexado. NÃO zera a coluna text legada
# (o serializer tem fallback pra ela) — uma limpeza posterior pode rodar após validar.
#
# Uso:
#   docker exec lafiga_api bundle exec rails battle_maps:backfill_background
#   docker exec -e DRY_RUN=1 lafiga_api bundle exec rails battle_maps:backfill_background
namespace :battle_maps do
  desc 'Migra background base64 (coluna text) → Active Storage blob. Idempotente. DRY_RUN=1 simula.'
  task backfill_background: :environment do
    require 'stringio'

    dry = ENV['DRY_RUN'] == '1'
    re  = %r{\Adata:image/(png|jpe?g|webp|gif);base64,([A-Za-z0-9+/=\s]+)\z}i
    counts = Hash.new(0)

    BattleMap.with_attached_background_image.find_each(batch_size: 50) do |bm|
      counts[:total] += 1

      if bm.background_image.attached?
        counts[:already_attached] += 1
        next
      end

      raw = bm.background_image_url
      if raw.blank?
        counts[:no_background] += 1
        next
      end

      m = re.match(raw)
      unless m
        counts[:not_data_uri] += 1
        warn "map ##{bm.id} '#{bm.name}': background_image_url não é data URI base64 (pulado)"
        next
      end

      fmt  = m[1].downcase
      mime = fmt == 'jpg' ? 'jpeg' : fmt
      ext  = mime == 'jpeg' ? 'jpg' : mime

      begin
        bytes = Base64.strict_decode64(m[2].gsub(/\s+/, ''))
      rescue ArgumentError
        counts[:decode_failed] += 1
        warn "map ##{bm.id} '#{bm.name}': base64 malformado (pulado)"
        next
      end

      if bytes.blank?
        counts[:decode_failed] += 1
        next
      end

      kb = (bytes.bytesize / 1024.0).round
      if dry
        counts[:would_migrate] += 1
        puts "[dry] map ##{bm.id} '#{bm.name}' → #{kb}KB image/#{mime}"
        next
      end

      bm.background_image.attach(
        io: StringIO.new(bytes),
        filename: "bg-#{bm.id}.#{ext}",
        content_type: "image/#{mime}",
      )
      counts[:migrated] += 1
      puts "map ##{bm.id} '#{bm.name}' migrado (#{kb}KB image/#{mime})"
    end

    puts "== backfill background #{dry ? '(DRY RUN) ' : ''}== #{counts.sort.to_h.inspect}"
  end
end
