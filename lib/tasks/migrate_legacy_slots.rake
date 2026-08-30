# Traz as linhas gravadas para os slots CANONICOS, seguindo
# `SheetItem::SLOT_ALIASES` — hoje `circlet`->`helmet` e `quiver`/`bag`->`back`.
#
#   bundle exec rake dnd:migrate_legacy_slots            # DRY RUN (padrao)
#   APPLY=1 bundle exec rake dnd:migrate_legacy_slots    # aplica
#
# ⚠️ Le a tabela de aliases em vez de nomear os slots: a primeira versao desta
# rake cobria so `quiver`/`bag` e deixou para tras um `circlet` de PROD, da
# fusao anterior — um Diadema equipado numa casa morta, invisivel na silhueta.
# Toda fusao futura fica coberta so por acrescentar o alias.
#
# Aljava e bolsa disputavam duas casas do boneco e passaram a disputar uma: e
# uma coisa de cada vez nas costas. A escolha nao aperta o arqueiro porque o
# CINTO tem slot livre que aceita aljava — mochila nas costas e aljava na
# cintura continua possivel.
#
# ⚠️ Sem esta migracao as linhas gravadas ficam com um slot que ja nao esta em
# `SheetItem::ALL_SLOTS`: a validacao passa a recusa-las e o boneco procura por
# `back`, entao a aljava equipada SOME da silhueta ate alguem tocar na linha.
# O `canonicalize_slot` conserta no proximo save, mas ninguem garante que haja
# um proximo save.
#
# COLISAO: um personagem com aljava E bolsa equipadas nao cabe no slot unico.
# A rake NAO escolhe por ele — relata e deixa as duas como estao, para o mestre
# decidir. Medido antes de escrever isto: zero colisoes.
namespace :dnd do
  desc 'Traz as linhas gravadas para os slots canonicos (APPLY=1 aplica)'
  task migrate_legacy_slots: :environment do
    apply = ENV['APPLY'].present?
    legados = SheetItem.where(slot: SheetItem::SLOT_ALIASES.keys)

    # Colisao e duas linhas equipadas que caem no MESMO slot canonico — o slot
    # unico nao comporta as duas, e adivinhar qual fica seria decidir pelo
    # jogador. Agrupar so por ficha marcaria falso positivo: um `circlet` e uma
    # `quiver` na mesma ficha vao para casas DIFERENTES (helmet e back).
    colisoes = legados.where(equipped: true)
                      .group_by { |si| [si.sheet_id, SheetItem.canonicalize_slot(si.slot)] }
                      .select { |_, v| v.size > 1 }

    puts "[dnd:migrate_legacy_slots]#{' DRY RUN —' unless apply} #{legados.count} linha(s) com slot legado"

    colisoes.each do |(sheet_id, canonico), linhas|
      nome = Sheet.find_by(id: sheet_id)&.character&.name
      puts "  ⚠️ #{nome.inspect} tem #{linhas.size} equipadas para `#{canonico}` " \
           "(#{linhas.map(&:item_name).inspect}) — DEIXADAS como estao"
    end
    ids_em_colisao = colisoes.values.flatten.map(&:id)

    movidos = 0
    ActiveRecord::Base.transaction do
      legados.where.not(id: ids_em_colisao).find_each do |si|
        dono = si.sheet&.character&.name
        canonico = SheetItem.canonicalize_slot(si.slot)
        puts "  #{dono.inspect}: #{si.item_name.inspect} #{si.slot} -> #{canonico}"
        movidos += 1
        next unless apply

        # `update_column` de proposito: o item pode nao passar em validacoes
        # alheias a esta migracao (proficiencia, por exemplo), e nao e este o
        # momento de as impor — so o nome do slot muda.
        si.update_column(:slot, canonico)
      end
    end

    puts "  #{movidos} linha(s) canonicalizada(s), #{ids_em_colisao.size} deixada(s) em colisao"
    puts '  (nada foi gravado — repita com APPLY=1)' unless apply
  end
end
