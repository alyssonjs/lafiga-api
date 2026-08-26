# frozen_string_literal: true

# Reconstrói os 7 pacotes de equipamento a partir do PHB (pág. 151).
#
#   bin/rails dnd:seed_phb_packs            # aplica
#   DRY_RUN=1 bin/rails dnd:seed_phb_packs  # só relata
#
# ⚠️ Não é só "linkar": o conteúdo que estava no banco DIVERGIA do livro. O
# Pacote de Aventureiro tinha 7 linhas, sem pé de cabra, martelo nem os 10
# pítons, e com um "Saco" que o livro não lista. Reconstruir da fonte conserta
# o link E o dado.
#
# `props['contents']` deixa de ser `["Mochila", "Tochas (10)"]` e passa a
# `[{item_index:, quantity:, raw:}]`. O `raw` (texto do livro) fica SEMPRE —
# se um dia o link quebrar, a linha continua legível.
#
# Depende de `dnd:seed_phb_gear`: sem a base, 28 das linhas apontam para itens
# que não existem.
namespace :dnd do
  desc 'Reconstrói os pacotes de equipamento a partir do PHB'
  task seed_phb_packs: :environment do
    dry = ENV['DRY_RUN'].present?
    seed = JSON.parse(File.read(Rails.root.join('db', 'data', 'packs_seed.json')))
    stats = Hash.new(0)
    faltando = []
    puts "== seed_phb_packs #{'(DRY RUN)' if dry} =="

    # 1. Itens citados só nos pacotes (não estão em tabela nenhuma do PHB).
    seed['itens_so_no_pacote'].each do |idx, nome|
      next if Item.exists?(api_index: idx)

      Item.create!(api_index: idx, name: nome, kind: 'gear',
                   source: 'PHB — Pacotes de Equipamento') unless dry
      stats[:itens_de_pacote_criados] += 1
    end

    # 2. Os pacotes.
    seed['pacotes'].each do |p|
      pack = Item.find_by(api_index: p['api_index'])
      if pack.nil?
        stats[:pacote_ausente] += 1
        warn "  ⚠️ pacote não existe no catálogo: #{p['api_index']}"
        next
      end

      conteudo = p['contents'].map do |c|
        # Tenta o índice canônico e cai no REPARADO: `dnd:seed_phb_gear`
        # completa item existente mantendo o api_index antigo (`pitons`,
        # `racoes`, `corda-15m`) em vez de renomear — renomear quebraria
        # referências de fichas já provisionadas.
        alvo = Item.find_by(api_index: c['item_index'])
        alvo ||= c['fallback_index'].present? ? Item.find_by(api_index: c['fallback_index']) : nil
        if alvo.nil?
          # NÃO descartar: a linha fica legível pelo `raw` e sai no relatório.
          faltando << "#{p['name']}: #{c['item_index']} (#{c['raw']})"
          { 'item_index' => nil, 'quantity' => c['quantity'], 'raw' => c['raw'] }
        else
          { 'item_index' => alvo.api_index, 'name' => alvo.name,
            'quantity' => c['quantity'], 'raw' => c['raw'] }
        end
      end

      novos = pack.props.to_h.merge('contents' => conteudo)
      mudou = novos != pack.props.to_h
      mudou ||= pack.value_gp.blank?
      unless dry
        pack.update!(props: novos, value_gp: pack.value_gp.presence || p['value_gp'])
      end
      stats[mudou ? :pacotes_reconstruidos : :ja_ok] += 1
      ligados = conteudo.count { |c| c['item_index'] }
      puts "  #{p['name']}: #{ligados}/#{conteudo.size} ligados"
    end

    if faltando.any?
      puts "\n⚠️ ingredientes de pacote sem item no catálogo (#{faltando.size}):"
      faltando.each { |f| puts "   #{f}" }
    end
    puts "\n== resultado =="
    stats.sort.each { |k, v| puts format('  %-26s %d', k, v) }
    puts "\n(DRY RUN — nada foi gravado)" if dry
  end
end
