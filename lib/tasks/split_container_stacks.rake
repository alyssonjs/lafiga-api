# Separa PILHAS de recipiente (aljava, bolsa com capacidade) em linhas
# individuais — uma por unidade.
#
#   bundle exec rake dnd:split_container_stacks            # DRY RUN (padrao)
#   APPLY=1 bundle exec rake dnd:split_container_stacks    # aplica
#
# ## Por que
#
# Cada recipiente guarda um CONTEUDO PROPRIO: a municao aponta para o id da
# aljava (`props_json['quiver_sheet_item_id']`), o item guardado aponta para o
# id da bolsa. Numa linha "Aljava x2" as duas unidades sao o MESMO id —
# equipar uma equipava as duas, e nao havia onde pendurar dois conteudos
# diferentes. O `stack_or_create!` passou a recusar essas pilhas; este rake
# desfaz as que ja existiam.
#
# ## ⚠️ A selecao NAO usa `bag?`
#
# O leitor tolerante do `bag?` casa por NOME ("bolsa", "sacola") e no banco de
# dev isso pega "bolsa PO x120" — que e DINHEIRO, nao recipiente. Separa-la
# criaria 120 linhas de moeda. A regra e `SheetItem.container_instance?`:
# aljava pelo leitor tolerante (o conceito e antigo e muita ficha so tem o
# nome), bolsa SO pela capacidade declarada no catalogo.
#
# ## O que faz
#
# Para cada pilha com quantity > 1: deixa a linha original com 1 e cria N-1
# clones (mesmo catalogo/props/notes/source), NAO-equipados e sem slot — a
# unidade equipada continua sendo UMA so, a original. O conteudo ja apontado
# para o id original permanece onde estava.
namespace :dnd do
  desc 'Separa pilhas de recipiente (aljava/bolsa) em linhas individuais. APPLY=1 para aplicar.'
  task split_container_stacks: :environment do
    aplicar = ENV['APPLY'].to_s == '1'
    puts(aplicar ? '== APLICANDO ==' : '== DRY RUN (use APPLY=1 para aplicar) ==')

    pilhas = SheetItem.where('quantity > 1').select { |i| SheetItem.container_instance?(i) }
    if pilhas.empty?
      puts 'Nenhuma pilha de recipiente encontrada.'
      next
    end

    criadas = 0
    pilhas.each do |pilha|
      extras = pilha.quantity.to_i - 1
      puts format(
        '  #%<id>d sheet=%<sheet>d %<nome>s x%<qtd>d  ->  1 + %<extras>d linha(s) nova(s)%<eq>s',
        id: pilha.id, sheet: pilha.sheet_id, nome: pilha.item_name.inspect,
        qtd: pilha.quantity, extras: extras,
        eq: pilha.equipped? ? " (equipada em #{pilha.slot} — so a original continua equipada)" : '',
      )
      next unless aplicar

      SheetItem.transaction do
        pilha.lock!
        extras.times do
          clone = pilha.dup
          clone.quantity = 1
          clone.equipped = false
          clone.slot = nil
          clone.position = SheetItem.next_position_for(pilha.sheet_id)
          clone.save!
          criadas += 1
        end
        pilha.update!(quantity: 1)
      end
    end

    puts aplicar ? "OK: #{criadas} linha(s) criada(s)." : "Seriam criadas #{pilhas.sum { |p| p.quantity.to_i - 1 }} linha(s)."
  end
end
