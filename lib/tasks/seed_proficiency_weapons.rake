# frozen_string_literal: true

# FASE 0 do catálogo — CATEGORIA DE ARMA e ARMA.
#
#   bundle exec rake dnd:seed_proficiency_weapons            # aplica
#   DRY_RUN=1 bundle exec rake dnd:seed_proficiency_weapons  # só relata
#
# ⚠️ O tipo mais sujo dos oito, e por isso o último. O que foi medido:
#
#   - a MESMA ficha guarda TRÊS vocabulários no mesmo array:
#     ["simple", "hand_crossbow", "longsword", "rapieiras", "shortsword"]
#      slug EN     slug EN         slug EN      pt-BR PLURAL   slug EN
#   - `class_rules.rb` escreve pt-BR por extenso ('rapieiras', 'espadas
#     longas') e TRÊS mapas rivais traduzem: `class_rules.rb` (20 pares),
#     `class_proficiency_adapter.rb` (22) e `class_rules_helper.rb` (49);
#   - o front tem DOIS catálogos: `weaponDatabase.ts` (37 armas, 45 arquivos
#     consomem) e `proficiencyLabels.ts` (o rótulo exibido) — e eles DISCORDAM
#     em cinco nomes;
#   - `proficiencyLabels.ts` produz rótulos PLURAIS separados ("Espadas Longas"
#     é um label diferente de "Espada Longa"), o que multiplicaria as linhas.
#
# ⚠️ O CANÔNICO é o nome de `weaponDatabase.ts` — mesma regra da ferramenta: o
# catálogo da ENTIDADE que o jogador manuseia vence o rótulo. São 45 arquivos a
# consumi-lo, e é contra ele que `isWeaponProficient` casa. Os cinco nomes de
# `proficiencyLabels.ts` entram como apelido.
namespace :dnd do
  # nome canônico (weaponDatabase), sub-categoria, [apelidos]
  #
  # Os apelidos cobrem, por arma: o slug inglês, o plural pt-BR que
  # `class_rules.rb` grava, o rótulo exibido quando difere, e o nome que
  # `race_rules.yml` usa.
  ARMAS = [
    # ── simples, corpo a corpo ────────────────────────────────────────────
    ['Porrete',        'simple_melee',  ['club', 'clavas', 'Clava']],
    ['Adaga',          'simple_melee',  %w[dagger adagas]],
    ['Clava Grande',   'simple_melee',  ['greatclub', 'clavas grandes']],
    ['Machadinha',     'simple_melee',  %w[handaxe machadinhas]],
    ['Azagaia',        'simple_melee',  %w[javelin azagaias]],
    ['Martelo Leve',   'simple_melee',  ['light-hammer', 'light_hammer', 'martelos leves']],
    ['Maça',           'simple_melee',  %w[mace macas maças]],
    ['Bordão',         'simple_melee',  %w[quarterstaff bordoes bordões]],
    ['Foice Curta',    'simple_melee',  %w[sickle foices Foice]],
    ['Lança',          'simple_melee',  %w[spear lancas lanças]],
    # ── simples, à distância ──────────────────────────────────────────────
    ['Besta Leve',     'simple_ranged', ['light-crossbow', 'light_crossbow', 'bestas_leves', 'bestas leves']],
    ['Dardo',          'simple_ranged', %w[dart dardos]],
    ['Arco Curto',     'simple_ranged', ['shortbow', 'shortbows', 'Arcos Curtos', 'arcos curtos']],
    ['Funda',          'simple_ranged', %w[sling fundas]],
    # ── marciais, corpo a corpo ───────────────────────────────────────────
    ['Machado de Batalha', 'martial_melee', ['battleaxe', 'machados de batalha']],
    ['Mangual',            'martial_melee', %w[flail manguais]],
    ['Glaive',             'martial_melee', %w[glaive glaives]],
    ['Machado Grande',     'martial_melee', ['greataxe', 'machados grandes']],
    ['Espada Grande',      'martial_melee', ['greatsword', 'espadas grandes']],
    ['Alabarda',           'martial_melee', %w[halberd alabardas]],
    ['Lança de Montaria',  'martial_melee', ['lance', 'Lança Montada', 'lancas de montaria']],
    ['Espada Longa',       'martial_melee', ['longsword', 'longswords', 'Espadas Longas', 'espadas longas']],
    ['Malho',              'martial_melee', %w[maul Marreta malhos]],
    ['Morningstar',        'martial_melee', ['morningstar', 'Mangual de Cabeça', 'morningstars']],
    ['Pique',              'martial_melee', %w[pike piques]],
    ['Rapieira',           'martial_melee', %w[rapier rapiers rapieiras Rapieiras]],
    ['Cimitarra',          'martial_melee', %w[scimitar cimitarras]],
    ['Espada Curta',       'martial_melee', ['shortsword', 'shortswords', 'Espadas Curtas', 'espadas curtas']],
    ['Tridente',           'martial_melee', %w[trident tridentes]],
    ['Picareta de Guerra', 'martial_melee', ['warpick', 'picaretas de guerra']],
    ['Martelo de Guerra',  'martial_melee', ['warhammer', 'martelos de guerra']],
    ['Chicote',            'martial_melee', %w[whip chicotes]],
    # ── marciais, à distância ─────────────────────────────────────────────
    ['Zarabatana',   'martial_ranged', %w[blowgun zarabatanas]],
    ['Besta de Mão', 'martial_ranged', ['hand-crossbow', 'hand_crossbow', 'handcrossbow', 'bestas de mão', 'bestas de mao']],
    ['Besta Pesada', 'martial_ranged', ['heavy-crossbow', 'heavy_crossbow', 'bestas pesadas']],
    ['Arco Longo',   'martial_ranged', ['longbow', 'longbows', 'Arcos Longos', 'arcos longos']],
    ['Rede',         'martial_ranged', %w[net redes]],
  ].freeze

  CATEGORIAS_ARMA = [
    ['Armas Simples',  ['simple', 'simple-weapons', 'simple_weapons', 'armas simples']],
    ['Armas Marciais', ['martial', 'martial-weapons', 'martial_weapons', 'armas marciais']],
  ].freeze

  desc 'FASE 0 — semeia CATEGORIA DE ARMA e ARMA (DRY_RUN=1 relata)'
  task seed_proficiency_weapons: :environment do
    seco = ENV['DRY_RUN'].present?
    criados = atualizados = apelidos = 0

    poe = lambda do |prefixo, nome, categoria, sub, extras|
      idx = "#{prefixo}-#{Proficiency.normalize(nome).tr(' ', '-')}"
      p = Proficiency.find_or_initialize_by(api_index: idx)
      novo = p.new_record?
      p.assign_attributes(name: nome, category: categoria, sub_category: sub,
                          metadata: {}, source: 'PHB', published: true)
      if seco
        puts "  #{novo ? 'CRIARIA' : 'atualizaria'} #{idx.ljust(32)} #{nome} (#{sub})"
      else
        p.save!
        ([nome] + Array(extras)).each do |a|
          antes = ProficiencyAlias.count
          p.add_alias!(a)
          apelidos += 1 if ProficiencyAlias.count > antes
        end
      end
      novo ? criados += 1 : atualizados += 1
    end

    ActiveRecord::Base.transaction do
      CATEGORIAS_ARMA.each { |nome, extras| poe.call('wcat', nome, 'weapon_category', nil, extras) }
      ARMAS.each { |nome, sub, extras| poe.call('weap', nome, 'weapon', sub, extras) }
      raise ActiveRecord::Rollback if seco
    end

    puts "\n#{seco ? '[DRY RUN] ' : ''}armas: #{criados} criados, #{atualizados} já existiam, #{apelidos} apelidos novos"
    unless seco
      puts "  weapon_category #{Proficiency.of('weapon_category').count}"
      puts "  weapon          #{Proficiency.of('weapon').count}"
    end
  end
end
