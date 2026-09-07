# frozen_string_literal: true

# Anexa os TEXTOS das cenas do Inkarnate aos BattleMaps já importados.
#
# O import original trouxe terreno e objetos e deixou os textos para trás —
# 545 rótulos ("Inferninho", "Casa dos Foxcox", nomes de cidades do mapa-múndi)
# em 12 das 32 cenas. O JSON vem pronto no modelo do nosso MapToken
# (`db/data/inkarnate_textos.json`, ver gerar_inkarnate_textos.py — âncora
# centro/baseline MEDIDA contra o preview renderizado).
#
# Casamento pelo NOME DO FICHEIRO do fundo (`ink-scene-<sid>.webp`), a chave de
# todo o pipeline de cenas. Idempotente pelo id do token (`ink-text-<sid>-<eid>`):
# reimportar não duplica; REPOR=1 regrava os existentes (pega ajuste de âncora).
#
# Uso:
#   docker exec -e DRY_RUN=1 lafiga-web-1 bundle exec rails inkarnate:texts_import
#   docker exec lafiga-web-1 bundle exec rails inkarnate:texts_import
namespace :inkarnate do
  desc 'Anexa textos das cenas do Inkarnate. DRY_RUN=1 simula; REPOR=1 regrava os já importados.'
  task texts_import: :environment do
    arq = Rails.root.join('db/data/inkarnate_textos.json')
    abort "índice não encontrado: #{arq}" unless File.exist?(arq)

    dry = ENV['DRY_RUN'] == '1'
    repor = ENV['REPOR'] == '1'
    indice = JSON.parse(File.read(arq))

    # sid → BattleMap, pelo fundo anexado (a mesma chave do scenes_import)
    mapa_por_sid = {}
    ActiveStorage::Blob
      .joins(:attachments)
      .where(active_storage_attachments: { record_type: 'BattleMap', name: 'background_image' })
      .where('filename LIKE ?', 'ink-scene-%')
      .pluck('active_storage_attachments.record_id', :filename)
      .each do |record_id, filename|
        sid = filename[/\Aink-scene-(\d+)\.webp\z/, 1]
        mapa_por_sid[sid] = record_id if sid
      end

    counts = Hash.new(0)
    indice['cenas'].each do |sid, cena|
      map_id = mapa_por_sid[sid]
      next counts[:cena_sem_mapa] += 1 unless map_id

      m = BattleMap.find(map_id)
      atuais = m.tokens || []
      # ⚠️ REMOVE os `ink-text-<sid>-*` que saíram do índice — e SÓ esses. O
      # replay do censo ignorava remoções no formato `entityIds` e ressuscitou
      # 316 textos apagados no Inkarnate (o "Midbar" gigante do 1.x); corrigido
      # o censo, esta poda tira os fantasmas sem tocar em texto criado à mão.
      validos = cena['tokens'].map { |t| t['id'] }.to_set
      prefixo = "ink-text-#{sid}-"
      antes = atuais.size
      atuais = atuais.reject { |t| t['id'].to_s.start_with?(prefixo) && !validos.include?(t['id']) }
      removidos = antes - atuais.size
      por_id = atuais.each_with_index.to_h { |t, i| [t['id'], i] }
      novos = []
      trocados = 0
      cena['tokens'].each do |tok|
        if (i = por_id[tok['id']])
          next unless repor
          atuais[i] = tok
          trocados += 1
        else
          novos << tok
        end
      end
      if novos.empty? && trocados.zero? && removidos.zero?
        counts[:sem_mudanca] += 1
        next
      end
      counts[:textos_novos] += novos.size
      counts[:textos_regravados] += trocados
      counts[:textos_removidos] += removidos
      puts "#{dry ? '[dry] ' : ''}#{m.name} (#{sid}): +#{novos.size} textos#{trocados.positive? ? ", #{trocados} regravados" : ''}#{removidos.positive? ? ", -#{removidos} fantasmas" : ''}"
      next if dry

      # update_column: importar rótulo não é editar o mapa — não reordena a
      # lista nem dispara broadcast (o mesmo contrato da miniatura).
      m.update_column(:tokens, atuais + novos)
      counts[:mapas] += 1
    end

    puts "== textos #{dry ? '(DRY RUN) ' : ''}== #{counts.sort.to_h.inspect}"
  end
end
