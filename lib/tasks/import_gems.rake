# frozen_string_literal: true

# Importa as 52 gemas do mundo (homebrew), com poder, efeito em arma e em
# vestuário.
#
#   bin/rails dnd:import_gems            # importa/atualiza
#   DRY_RUN=1 bin/rails dnd:import_gems  # só relata
#
# Ficam em `material/gem` — o mesmo lugar das gemas do DMG, porque gema É
# insumo: a Gema Olho de Tigre já é ingrediente da Poção do Acerto Crítico.
# O encaixe em arma/vestuário entra como DADO (props); a mecânica de combate
# é trabalho à parte.
#
# ⚠️ A planilha tem duas unidades: a linha da gema diz "10PO" e a tabela de
# balanceamento diz "10 PL". Uma peça de platina vale 10 po — seguir a tabela
# faria toda gema valer 10x mais. A linha da gema manda (é o dado por item).
# Nome de gema batem entre fontes com prefixo a mais ("Gema Olho de Tigre" x
# "Olho de Tigre") e com acento. Normaliza os dois lados antes de comparar.
def chave_de_gema(nome)
  nome.to_s.unicode_normalize(:nfd).chars.reject { |c| c =~ /\p{Mn}/ }.join.downcase
      .gsub(/\b(gema|cristal|pedra)\b/, ' ')
      .gsub(/[^a-z0-9]+/, ' ').strip
end

namespace :dnd do
  desc 'Importa as gemas do mundo (52, com efeitos)'
  task import_gems: :environment do
    dry = ENV['DRY_RUN'].present?
    seed = JSON.parse(File.read(Rails.root.join('db', 'data', 'gems_seed.json')))
    stats = Hash.new(0)
    puts "== import_gems #{'(DRY RUN)' if dry} =="

    # ⚠️ A ORDEM importa: enriquecer PRIMEIRO, limpar depois. Onze das genéricas
    # do DMG têm o mesmo NOME de uma gema real — apagá-las antes destruiria a
    # referência de qualquer ficha que já as tenha, para recriar um item
    # equivalente com outro id. Enriquecer preserva o que o jogador tem.
    aproveitadas = []
    # chave normalizada -> item que REALMENTE ficou no banco para aquela gema.
    # ⚠️ Não dá para reachar pelo `api_index` do seed depois: quando a gema já
    # existia com outro índice (`mat-olho-de-tigre` vindo do Manual do
    # Alquimista), o enriquecimento MANTÉM o índice antigo de propósito — trocar
    # quebraria as fichas que já a têm. Guardar o objeto é o único jeito de
    # saber quem sobreviveu.
    resolvidas = {}

    seed.each do |g|
      item = Item.find_by(api_index: g['api_index'])
      # Gema homebrew que o mestre já tenha criado com o mesmo NOME: enriquece
      # em vez de duplicar.
      item ||= Item.where(kind: 'material', category: 'gem')
                   .where('lower(name) = ?', g['name'].downcase).first

      if item.nil?
        unless dry
          nova = Item.create!(api_index: g['api_index'], name: g['name'], kind: 'material',
                              category: 'gem', value_gp: g['value_gp'], source: g['source'],
                              description: g['description'], props: g['props'])
          resolvidas[chave_de_gema(g['name'])] = nova
        end
        stats[:criadas] += 1
        next
      end

      # Genérica do DMG sendo promovida: a planilha SUBSTITUI, não completa. O
      # Rubi do DMG custa 1000 po e o do mundo, 5000 — deixar o preço velho
      # deixaria a gema brigando com o próprio tier (VI = 5000 na tabela de
      # balanceamento). Já a gema que o mestre criou à mão só tem os buracos
      # preenchidos: preço que ele digitou é decisão dele.
      generica = item.source == 'PHB/DMG'
      mudou = {}
      mudou[:value_gp]    = g['value_gp']    if generica || item.value_gp.blank?
      mudou[:description] = g['description'] if generica || item.description.blank?
      mudou[:source]      = g['source']      if generica || item.source.blank?
      # Poder, efeitos e tier são DO CATÁLOGO; o resto do props (edições do
      # mestre) fica intacto.
      novos = item.props.to_h.merge(g['props'])
      mudou[:props] = novos if novos != item.props.to_h
      item.update!(mudou) if mudou.any? && !dry
      aproveitadas << item.id
      resolvidas[chave_de_gema(g['name'])] = item
      stats[mudou.any? ? :genericas_promovidas : :ja_ok] += 1
    end

    # Duplicata por NOME vinda de outra fonte: o Manual do Alquimista já tinha
    # catalogado "Gema Olho de Tigre" (sem preço) e a planilha traz a mesma
    # pedra como "Olho de Tigre" (tier I, 10 po). Duas linhas para a mesma
    # gema quebrariam o elo que a receita precisa — o NPC ferreiro exigiria
    # uma das duas e o jogador teria a outra. A de fora é absorvida: as
    # receitas passam a apontar para a da planilha e ela some.
    #
    # O casamento só vale DENTRO de `material/gem` e só contra uma gema da
    # planilha: mesmo nome, já classificado como gema, é a mesma pedra.
    Item.where(kind: 'material', category: 'gem')
        .where.not(id: aproveitadas)
        .find_each do |dup|
      alvo = resolvidas[chave_de_gema(dup.name)]
      next if alvo.nil? || alvo.id == dup.id

      usos = CraftingRecipeIngredient.where(ingredient_item_id: dup.id)
      fichas = SheetItem.where(item_id: dup.id)
      puts "  ~ funde #{dup.name} (#{dup.api_index}) -> #{alvo.name} " \
           "(#{usos.count} receita(s), #{fichas.count} ficha(s))"
      unless dry
        usos.update_all(ingredient_item_id: alvo.id)
        fichas.update_all(item_id: alvo.id)
        dup.reload.destroy || warn("  ⚠️ não saiu: #{dup.errors.full_messages.first}")
      end
      stats[:duplicatas_fundidas] += 1
    end

    # Só agora saem as genéricas que NÃO viraram nenhuma gema real. O
    # `restrict_with_error` do model barra a que estiver em receita.
    Item.where(kind: 'material', category: 'gem', source: 'PHB/DMG')
        .where.not(id: aproveitadas)
        .find_each do |g|
      if dry
        stats[:genericas_a_remover] += 1
        next
      end
      if g.destroy
        stats[:genericas_removidas] += 1
      else
        stats[:genericas_mantidas_em_uso] += 1
        warn "  ⚠️ em uso, mantida: #{g.name} (#{g.errors.full_messages.first})"
      end
    end

    puts "\n== resultado =="
    stats.sort.each { |k, v| puts format('  %-28s %d', k, v) }
    puts "\n(DRY RUN — nada foi gravado)" if dry
  end
end
