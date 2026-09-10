# frozen_string_literal: true

# Auditoria das atrelagens de magia — o PORTÃO da fase 0.
#
#   bundle exec rake dnd:audit_spell_sources
#
# Só lê. Sai com 1 quando há atrelagem QUEBRADA (aponta para magia que não
# existe) — isso é defeito. As LACUNAS (raça sem magia estruturada, feature
# sem atrelação) são relatadas mas não derrubam: são trabalho por fazer, não
# defeito, e confundir os dois faz o portão perder o sentido.
namespace :dnd do
  desc 'Audita atrelagens de magia: quebradas (falha) e lacunas (relata)'
  task audit_spell_sources: :environment do
    falhas = 0

    puts '== atrelagens por fonte'
    SpellSource.group(:source_type).count.sort.each do |tipo, n|
      puts format('   %-12s %4d', tipo, n)
    end
    puts format('   %-12s %4d', 'TOTAL', SpellSource.count)

    puts "\n== por modo de conjuração"
    SpellSource.group(:casting_mode).count.sort.each { |m, n| puts format('   %-16s %4d', m, n) }

    puts "\n== integridade"

    # ⚠️ CORREÇÃO ao plano (R1): atrelagem apontando para magia inexistente é
    # IMPOSSÍVEL — há uma foreign key `spell_sources.spell_id → spells.id`. Eu
    # tinha escrito um guarda para isso e ele era código morto, a verificar o
    # que o banco já garante. Provado ao tentar injetar o defeito: o Postgres
    # recusou com `ForeignKeyViolation`.
    #
    # O risco REAL do `spells:replace NUKE=1` é outro e mais silencioso: ele faz
    # `SpellSource.delete_all` ANTES do `Spell.delete_all` — justamente por
    # causa da FK. As atrelagens não ficam quebradas: DESAPARECEM. Ninguém vê
    # erro; o personagem só deixa de ter a magia da raça.
    #
    # Por isso o guarda certo é de PRESENÇA: o que devia existir, existe?
    esperado = { 'Klass' => 1, 'SubKlass' => 1, 'Race' => 1, 'SubRace' => 1 }
    esperado.each do |tipo, minimo|
      n = SpellSource.where(source_type: tipo).count
      if n >= minimo
        puts format('   ✓ %-9s tem %d atrelagem(ns)', tipo, n)
      else
        falhas += 1
        puts format('   ✗ %-9s está VAZIO — o seed correu? `spells:replace NUKE=1` passou por aqui?', tipo)
      end
    end

    # Fonte que já não existe (raça apagada, subclasse removida).
    sem_fonte = SpellSource.select do |ss|
      SpellSource::SOURCE_TYPES.include?(ss.source_type) && ss.source_record.nil?
    end
    if sem_fonte.empty?
      puts '   ✓ 0 atrelagens apontam para fonte inexistente'
    else
      falhas += 1
      puts "   ✗ #{sem_fonte.size} atrelagens apontam para fonte inexistente"
      sem_fonte.first(5).each { |s| puts "       #{s.source_type}##{s.source_id}" }
    end

    # ── LACUNA: relatada, não derruba ─────────────────────────────────────
    puts "\n== lacunas (trabalho por fazer, não defeito)"

    # 1. Traits cuja chave promete magia mas que não têm dado estruturado.
    #
    # ⚠️ A primeira versão desta checagem olhava `t['grants']` no trait INLINE
    # da raça e reportava 7 lacunas — todas falsas. O trait inline é só uma
    # REFERÊNCIA por chave (`- { key: abyssal_legacy }`); os grants vivem em
    # `RaceRules.trait_definitions`. Os legados do Tiefling estão estruturados
    # lá, com nível e limite. Medir no lugar errado dá um número convincente e
    # errado — e este relatório chegou a ser citado como prova de que os
    # legados eram "só comentário".
    require 'yaml'
    yaml = YAML.load_file(Rails.root.join('config', 'race_rules.yml'))
    defs = RaceRules.trait_definitions || {}
    so_comentario = []

    tem_magia = lambda do |chave|
      d = defs[chave.to_s.to_sym] || defs[chave.to_s] || {}
      g = d[:grants] || d['grants']
      o = d[:options] || d['options']
      (g.is_a?(Hash) && (g[:spells] || g['spells']).present?) ||
        (o.is_a?(Hash) && (o[:spell_list] || o['spell_list']).present?)
    end

    varre = lambda do |no, nome_pai|
      next unless no.is_a?(Hash)

      nome = no['name'] || nome_pai
      Array(no['traits']).each do |t|
        next unless t.is_a?(Hash)

        chave = (t['key'] || t[:key]).to_s
        next unless chave =~ /legacy|spell|magic|cantrip|conjur/i
        # `legacy_resistance_fire` casa por conter "legacy" e é resistência a
        # dano, não magia — ruído que faria a lacuna mentir para cima.
        next if chave =~ /resistance|resist/i
        # estruturado no trait OU no catálogo de definições
        next if t['grants'].present? || t['options'].present? || tem_magia.call(chave)

        so_comentario << "#{nome}: #{chave}"
      end
      (no['subraces'] || {}).each_value { |sr| varre.call(sr, nome) } if no['subraces'].is_a?(Hash)
    end
    yaml.each_value { |r| varre.call(r, nil) } if yaml.is_a?(Hash)
    puts "   · traits de magia SEM dado estruturado (nem inline, nem no catálogo): #{so_comentario.size}"
    so_comentario.first(8).each { |t| puts "       #{t}" }

    # 1b. Definições de trait com magia que NENHUMA raça referencia — dado vivo
    #     que não chega a ninguém (hoje: `infernal_legacy`, substituído pelo par
    #     `thaumaturgy_cantrip` + `infernal_legacy_variant`).
    referenciadas = []
    colhe = lambda do |no|
      next unless no.is_a?(Hash)

      Array(no['traits']).each { |t| referenciadas << (t['key'] || t[:key]).to_s if t.is_a?(Hash) }
      (no['subraces'] || {}).each_value { |sr| colhe.call(sr) } if no['subraces'].is_a?(Hash)
    end
    yaml.each_value { |r| colhe.call(r) } if yaml.is_a?(Hash)
    orfas = defs.keys.map(&:to_s).select { |k| tem_magia.call(k) } - referenciadas.uniq
    puts "   · definições de trait COM magia que ninguém referencia: #{orfas.size}"
    orfas.first(8).each { |k| puts "       #{k}" }

    # 2. Cobertura de FEATURE — o que o pedido chama de "atrelar a features".
    por_feature = SpellSource.where(source_type: 'Feature').count
    de_subclasse = SpellSource.where(source_type: 'SubKlass').count
    puts "   · atrelagens por FEATURE: #{por_feature} (subclasse achatada: #{de_subclasse})"

    # 3. Talentos que concedem magia no texto mas não no dado.
    sem_regra = FeatRules::RULES.count do |_k, v|
      v[:description].to_s =~ /truque|magia|conjur/i && (v[:special_rules] || {}).empty?
    end
    puts "   · talentos que falam de magia e não têm regra estruturada: #{sem_regra}"

    if falhas.positive?
      puts "\nFALHOU: #{falhas} problema(s) de integridade."
      exit 1
    end
    puts "\n✓ integridade OK"
  end
end
