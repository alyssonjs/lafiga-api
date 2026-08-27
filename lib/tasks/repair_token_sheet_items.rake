# frozen_string_literal: true

# Resolve linhas de ficha que guardam o TOKEN cru do assistente no lugar do
# nome do item ("explorer-pack", "rapieira", "handaxe:2", "simple:any").
#
#   bin/rails dnd:repair_token_sheet_items            # aplica
#   DRY_RUN=1 bin/rails dnd:repair_token_sheet_items  # só relata
#
# São resíduo do bug em que o wizard mandava o token como `item_name`: o
# backend procurava um item com esse nome, não achava, e a linha nascia morta.
# A causa está corrigida; isto limpa o passado.
#
# ⚠️ NUNCA APAGA. Uma dessas linhas pode ser o ÚNICO registro de um item a que
# o personagem tem direito (um `pacote-diplomata` que jamais expandiu) — um
# DELETE tiraria equipamento de quem o merece. O rake só RESOLVE o que
# consegue e RELATA o resto; a decisão sobre o que sobra é do mestre.
namespace :dnd do
  desc 'Resolve linhas de ficha com token do assistente no lugar do nome'
  task repair_token_sheet_items: :environment do
    dry = ENV['DRY_RUN'].present?
    puts "== repair_token_sheet_items #{'(DRY RUN)' if dry} =="

    stats = Hash.new(0)
    nao_resolvidos = Hash.new(0)
    duplicatas = []

    # Só linhas SEM índice cujo nome parece token (minúsculo, sem espaço).
    alvos = SheetItem.where(item_index: [nil, '']).select do |si|
      n = si.item_name.to_s
      n.present? && n == n.downcase && n.match?(/\A[a-z0-9:_-]+\z/)
    end
    puts "  linhas suspeitas: #{alvos.size} em #{alvos.map(&:sheet_id).uniq.size} ficha(s)\n\n"

    resolver = ItemResolver.new

    alvos.each do |si|
      bruto = si.item_name.to_s

      # `handaxe:2` = token + quantidade; `simple:any` = escolha NÃO FEITA.
      if bruto.end_with?(':any') || bruto == 'any'
        nao_resolvidos["#{bruto} (escolha nunca feita)"] += 1
        stats[:escolha_pendente] += 1
        next
      end

      token, qtd = bruto.split(':')
      qtd = qtd.to_i.positive? ? qtd.to_i : nil

      # Mesmo mapa do provisionamento — token → api_index do catálogo.
      indice = CharacterProvisioningService::TOKEN_PARA_INDICE[token] || token
      item = Item.find_by(api_index: indice)
      item ||= begin
        resolver.resolve(name: token.tr('-', ' '), category: si.category)
      rescue StandardError
        nil
      end

      if item.nil?
        nao_resolvidos["#{bruto} (sem item no catálogo)"] += 1
        stats[:sem_catalogo] += 1
        next
      end

      # ⚠️ A ficha JÁ tem esse item? Então NÃO resolve — relata e segue.
      #
      # Resolver criaria "Martelo de Guerra" duas vezes: uma linha plausível
      # que o mestre pode nem notar, enquanto o token cru se denuncia sozinho.
      # E o caso é genuinamente AMBÍGUO: `handaxe:2` são duas machadinhas — se
      # a ficha já tem uma, o total certo pode ser 2 ou 3, e só o mestre sabe.
      # Regra da casa: resolver o que é inequívoco, relatar o resto.
      if SheetItem.where(sheet_id: si.sheet_id, item_id: item.id).where.not(id: si.id).exists?
        duplicatas << "ficha #{si.sheet_id}: #{bruto} → #{item.name} (a ficha já tem — não mexi)"
        stats[:duplicata_relatada] += 1
        next
      end

      puts "  ~ ficha #{si.sheet_id}: #{bruto.ljust(22)} → #{item.name}#{qtd ? " ×#{qtd}" : ''}"
      unless dry
        si.update!(
          item_name: item.name,
          item_index: item.api_index,
          item_id: item.id,
          **(qtd ? { quantity: qtd } : {}),
        )
      end
      stats[:resolvidos] += 1
    end

    if nao_resolvidos.any?
      puts "\n  ── não resolvidos (ficam como estão, para o mestre decidir) ──"
      nao_resolvidos.sort_by { |_, v| -v }.each { |nome, n| puts "    #{nome}: #{n}" }
    end
    if duplicatas.any?
      puts "\n  ── ⚠️ resolveram para item que a ficha JÁ tem (revisar) ──"
      duplicatas.first(15).each { |d| puts "    #{d}" }
      puts "    … e mais #{duplicatas.size - 15}" if duplicatas.size > 15
    end

    puts "\n== resultado =="
    stats.sort.each { |k, v| puts format('  %-22s %d', k, v) }
    puts "\n(DRY RUN — nada foi gravado)" if dry
  end
end
