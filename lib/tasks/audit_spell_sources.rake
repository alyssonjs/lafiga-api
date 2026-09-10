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

    # 1. Magias raciais que vivem só em COMENTÁRIO no YAML.
    #    O `abyssal_legacy` do Tiefling diz, em comentário, "3º: Raio
    #    Adoecente; 5º: Cativar, 1/LDesc cada" — e nenhum código o lê.
    require 'yaml'
    yaml = YAML.load_file(Rails.root.join('config', 'race_rules.yml'))
    so_comentario = []
    varre = lambda do |no, nome_pai|
      next unless no.is_a?(Hash)

      nome = no['name'] || nome_pai
      linhas_traits = Array(no['traits'])
      linhas_traits.each do |t|
        next unless t.is_a?(Hash)
        # trait SEM grants nem options, cuja chave sugere magia
        next if t['grants'].present? || t['options'].present?
        next unless t['key'].to_s =~ /legacy|spell|magic|cantrip|conjur/i

        so_comentario << "#{nome}: #{t['key']}"
      end
      (no['subraces'] || {}).each_value { |sr| varre.call(sr, nome) } if no['subraces'].is_a?(Hash)
    end
    yaml.each_value { |r| varre.call(r, nil) } if yaml.is_a?(Hash)
    puts "   · traits de magia SEM dado estruturado (só comentário): #{so_comentario.size}"
    so_comentario.first(8).each { |t| puts "       #{t}" }

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
