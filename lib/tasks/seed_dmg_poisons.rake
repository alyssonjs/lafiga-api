# Semeia a tabela de VENENOS do DMG (cap. 8, "Venenos").
#
#   bundle exec rake dnd:seed_dmg_poisons            # aplica
#   DRY_RUN=1 bundle exec rake dnd:seed_dmg_poisons  # so relata
#
# Idempotente: casa por `api_index`, nunca duplica, nunca sobrescreve item
# existente.
#
# ⚠️ PROVENIENCIA: ao contrario de `seed_phb_tools`/`seed_phb_consumables`, que
# saem do `livro_do_jogador.txt` do repo, o texto do DMG NAO esta aqui. Nomes,
# precos e CDs vem do conhecimento do modelo. Marcados com `source: 'DMG'` para
# ficarem distinguiveis e auditaveis: se um preco ou CD estiver errado, o mestre
# corrige no admin sem tocar em nada do PHB.
#
# Vetor (contato/ingerido/inalado/ferimento) fica no inicio da descricao — e o
# que muda COMO se aplica, entao precisa estar visivel no card.
namespace :dnd do
  # [nome, api_index, custo em PO, descricao]
  DMG_POISONS = [
    ['Sangue de Assassino', 'sangue-de-assassino', 150,
     'Ingerido. CD 10 de Constituição ou sofre 6 (1d12) de dano de veneno e fica envenenada por 24 horas. Sucesso: metade do dano e não fica envenenada.'],
    ['Fumaça de Othur Queimado', 'fumaca-de-othur-queimado', 500,
     'Inalado. CD 13 de Constituição ou sofre 10 (3d6) de dano de veneno e repete o teste no início de cada turno; a cada falha sofre 3 (1d6) e o máximo de PV cai no mesmo valor. Termina após 3 sucessos.'],
    ['Muco de Rastejante', 'muco-de-rastejante', 200,
     'Contato. CD 13 de Constituição ou fica envenenada por 1 minuto e paralisada enquanto envenenada. Repete o teste no fim de cada turno.'],
    ['Veneno Drow', 'veneno-drow', 200,
     'Ferimento. CD 13 de Constituição ou fica envenenada por 1 hora. Se falhar por 5 ou mais, fica inconsciente enquanto envenenada — acorda se sofrer dano ou alguém usar uma ação para acordá-la.'],
    ['Essência de Éter', 'essencia-de-eter', 300,
     'Inalado. CD 15 de Constituição ou fica envenenada por 8 horas e inconsciente enquanto envenenada. Acorda se sofrer dano ou alguém usar uma ação para acordá-la.'],
    ['Malícia', 'malicia', 250,
     'Inalado. CD 15 de Constituição ou fica envenenada por 1 hora e cega enquanto envenenada.'],
    ['Lágrimas da Meia-Noite', 'lagrimas-da-meia-noite', 1_500,
     'Ingerido. Sem efeito até a meia-noite. CD 17 de Constituição ou sofre 31 (9d6) de dano de veneno; metade em caso de sucesso.'],
    ['Óleo de Taggit', 'oleo-de-taggit', 400,
     'Contato. CD 13 de Constituição ou fica envenenada por 24 horas e inconsciente enquanto envenenada. Acorda se sofrer dano.'],
    ['Tintura Pálida', 'tintura-palida', 250,
     'Ingerido. CD 16 de Constituição ou sofre 3 (1d6) de dano de veneno e fica envenenada. Repete o teste a cada 24 horas; cada falha repete o dano e reduz o máximo de PV. Termina após 7 sucessos.'],
    ['Veneno de Verme Púrpura', 'veneno-de-verme-purpura', 2_000,
     'Ferimento. CD 19 de Constituição ou sofre 42 (12d6) de dano de veneno; metade em caso de sucesso.'],
    ['Veneno de Serpente', 'veneno-de-serpente', 200,
     'Ferimento. CD 11 de Constituição ou sofre 10 (3d6) de dano de veneno; metade em caso de sucesso.'],
    ['Torpor', 'torpor', 600,
     'Ingerido. CD 15 de Constituição ou fica incapacitada por 4d6 horas.'],
    ['Soro da Verdade', 'soro-da-verdade', 150,
     'Ingerido. CD 11 de Constituição ou fica envenenada por 1 hora. Enquanto envenenada, não consegue mentir conscientemente — como sob efeito de Zona da Verdade.'],
    ['Veneno de Wyvern', 'veneno-de-wyvern', 1_200,
     'Ferimento. CD 15 de Constituição ou sofre 24 (7d6) de dano de veneno; metade em caso de sucesso.'],
  ].freeze

  desc 'Semeia os 14 venenos do DMG (DRY_RUN=1 so relata)'
  task seed_dmg_poisons: :environment do
    dry = ENV['DRY_RUN'].present?
    criados = []
    pulados = []

    DMG_POISONS.each do |name, api_index, cost_gp, desc|
      if Item.find_by(api_index: api_index)
        pulados << api_index
        next
      end

      criados << api_index
      next if dry

      Item.create!(
        api_index: api_index,
        name: name,
        kind: 'consumable',
        category: 'poison',
        description: desc,
        props: { 'cost_cp' => (cost_gp.to_f * 100).round },
        source: 'DMG',
      )
    end

    puts "[dnd:seed_dmg_poisons]#{' DRY RUN —' if dry} #{criados.size} criado(s), #{pulados.size} ja existia(m)"
    puts "  criados: #{criados.join(', ')}" if criados.any?
    total = Item.where(kind: 'consumable', category: 'poison').count
    puts "  venenos no catalogo agora: #{total}"
  end
end
