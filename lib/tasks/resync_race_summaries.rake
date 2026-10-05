# frozen_string_literal: true

# FASE 4 do editor de raças — repõe nas fichas JÁ existentes o que mudou na raça.
#
#   bundle exec rake dnd:resync_race_summaries
#   DRY_RUN=1 RACE=dwarf bundle exec rake dnd:resync_race_summaries
#
# ⚠️ Medido numa ficha real: sem isto a ficha fica INCOERENTE consigo mesma.
# A mecânica propaga ao vivo (o `RaceProducer` lê `RaceRules.apply` a cada
# summary), mas a vitrine fica presa no `race_summary` materializado no
# provisionamento — o personagem passa a resistir a contundente e a lista de
# traços não menciona porquê.
#
# O editor já dispara isto sozinho ao gravar. Este rake é o caminho manual:
# depois de um deploy que mexa no `race_rules.yml`, ou para repor uma raça que
# falhou na hora.
#
# ⚠️ PRESERVA AS ESCOLHAS DO JOGADOR. Recompor o snapshot só pela regra apaga
# a ferramenta que o Anão escolheu e o idioma que o Humano escolheu — eles
# vivem no snapshot e não na regra. O serviço trata disso; ver
# `Races::ResyncSummaries`.
namespace :dnd do
  desc 'FASE 4 — repõe `race_summary` das fichas a partir da regra canônica. Idempotente. RACE= e DRY_RUN=1.'
  task resync_race_summaries: :environment do
    dry = %w[1 true yes].include?(ENV['DRY_RUN'].to_s.strip.downcase)
    slug = ENV['RACE'].to_s.strip

    # ⚠️ A forma GLOBAL reescreve o snapshot de TODA ficha do banco, e exige
    # `ALL=1` de propósito: sem a raça, um `rake dnd:resync_race_summaries`
    # distraído mexe em tudo. (Aprendido da maneira difícil ao construir isto.)
    if slug.blank? && !%w[1 true yes].include?(ENV['ALL'].to_s.strip.downcase)
      puts '⚠️ sem `RACE=`, isto reescreve o snapshot de TODAS as fichas.'
      puts '   Confirme com `ALL=1`, ou meça antes com `DRY_RUN=1 ALL=1`.'
      next
    end

    raca = nil
    if slug.present?
      raca = Race.find_by(api_index: slug) || Race.find_by(id: slug)
      if raca.nil?
        puts "⚠️ raça #{slug.inspect} não encontrada"
        next
      end
    end

    alvo = raca ? "#{raca.name} (#{raca.api_index})" : 'TODAS as raças'
    puts "== resync de `race_summary` — #{alvo}#{dry ? '  [DRY_RUN]' : ''}\n\n"

    rel = Races::ResyncSummaries.call(race_id: raca&.id, dry_run: dry)

    puts "  fichas vistas:   #{rel.vistas}"
    puts "  #{dry ? 'mudariam' : 'gravadas'}:  #{rel.mudadas}\n\n"

    if rel.mudadas.zero?
      puts '  ✓ nada a fazer — as fichas já refletem a regra'
    else
      por_campo = Hash.new(0)
      rel.detalhes.each { |d| d[:mudou].each { |c| por_campo[c] += 1 } }
      puts '  campos tocados:'
      por_campo.sort_by { |_, n| -n }.each { |campo, n| puts format('     %-16s %d ficha(s)', campo, n) }
      puts
      puts '  ⚠️ DRY_RUN: nada foi gravado. Tire o DRY_RUN para aplicar.' if dry
    end
  end
end
