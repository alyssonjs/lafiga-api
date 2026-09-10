# frozen_string_literal: true

# FASE 0 das magias — atrelação a RAÇA e SUB-RAÇA.
#
#   bundle exec rake dnd:seed_spell_sources_innate            # aplica
#   DRY_RUN=1 bundle exec rake dnd:seed_spell_sources_innate  # só relata
#
# ⚠️ É REGISTRO, não autoridade. Quem concede magia racial continua a ser o
# `race_rules.yml`, lido por `RaceRules.apply` e pelo `KnownSpellsAggregator`.
# Migrar a autoridade para cá é uma fase própria, com paridade medida — nunca
# implícita, porque erra-se em silêncio e o sintoma é um personagem sem o
# truque da raça.
#
# ⚠️ Só toca em `origin: 'derived'`: o que o mestre atrelar à mão sobrevive a
# qualquer re-semeadura. Mesma regra das proficiências, e pelo mesmo motivo.
#
# ⚠️ POOL ABERTO fica de fora. O Alto Elfo tem
# `options: { choose: 1, spell_list: wizard, filters: { level: 0 } }` — isso é
# "escolha 1 truque de mago qualquer", e criar uma atrelação para cada truque
# de mago diria que a raça concede todos eles. Mesma regra que aplicámos a
# `options: :any` nas proficiências.
namespace :dnd do
  desc 'FASE 0 — atrela magias INATAS de raça/sub-raça (DRY_RUN=1 relata)'
  task seed_spell_sources_innate: :environment do
    require 'yaml'
    seco = ENV['DRY_RUN'].present?
    achados = []
    sem_magia = []
    pools_abertos = []

    yaml = YAML.load_file(Rails.root.join('config', 'race_rules.yml'))

    anda = lambda do |no, tipo, chave|
      next unless no.is_a?(Hash)

      id = no['id'] || chave
      nome = no['name'] || id

      Array(no['traits']).each do |t|
        next unless t.is_a?(Hash)

        # ── POOL: `options.spell_list` é lista inteira, não magia específica ──
        opts = t['options']
        if opts.is_a?(Hash) && opts['spell_list'].present?
          pools_abertos << "#{nome} (#{t['key']}): escolhe #{opts['choose']} de #{opts['spell_list']}"
          next
        end

        g = t['grants']
        next unless g.is_a?(Hash)

        Array(g['spells']).each do |entrada|
          next unless entrada.is_a?(Hash)

          slug = entrada['spell'].to_s
          spell = Spell.find_by(api_index: slug)
          if spell.nil?
            sem_magia << "#{nome} (#{t['key']}): #{slug.inspect}"
            next
          end

          # `usage` do YAML → `casting_mode` do catálogo.
          modo = case entrada['usage'].to_s
                 when 'at_will', 'atwill' then 'at_will'
                 when '' then 'with_slot'
                 else 'uses_per_rest'
                 end

          achados << {
            tipo: tipo, chave: id, nome: nome, spell: spell, trait: t['key'].to_s,
            modo: modo, ability: entrada['ability'].to_s.presence,
            nivel_magia: entrada['level']
          }
        end
      end

      (no['subraces'] || {}).each { |k, sr| anda.call(sr, 'SubRace', k) } if no['subraces'].is_a?(Hash)
    end
    yaml.each { |k, r| anda.call(r, 'Race', k) } if yaml.is_a?(Hash)

    # As chaves do YAML são slugs; o `source_id` precisa da linha real.
    resolve_fonte = lambda do |tipo, chave|
      tipo == 'Race' ? Race.find_by(api_index: chave) : SubRace.find_by(api_index: chave)
    end

    if seco
      puts "[DRY RUN] #{achados.size} atrelagens inatas derivadas:"
      achados.each do |a|
        alvo = resolve_fonte.call(a[:tipo], a[:chave])
        puts format('  %-8s %-22s %-24s %s%s', a[:tipo], a[:nome], a[:spell].name, a[:modo],
                    alvo ? '' : '  ⚠️ FONTE NÃO ENCONTRADA NA TABELA')
      end
      puts "\npools ABERTOS (deliberadamente fora): #{pools_abertos.size}"
      pools_abertos.each { |p| puts "  #{p}" }
      puts "\nmagias do YAML que o catálogo não tem: #{sem_magia.size}"
      sem_magia.each { |m| puts "  #{m}" }
      next
    end

    criados = 0
    erros = []
    ActiveRecord::Base.transaction do
      achados.each do |a|
        alvo = resolve_fonte.call(a[:tipo], a[:chave])
        if alvo.nil?
          erros << "#{a[:tipo]} #{a[:chave].inspect} não existe na tabela"
          next
        end

        linha = SpellSource.find_or_initialize_by(
          source_type: a[:tipo], source_id: alvo.id, spell_id: a[:spell].id
        )
        criados += 1 if linha.new_record?
        # ⚠️ Não rebaixa nem sobrescreve o que o mestre marcou como `manual`.
        next if linha.persisted? && linha.origin == 'manual'

        linha.origin = 'derived'
        linha.casting_mode = a[:modo]
        linha.always_prepared = true
        linha.ability_override = a[:ability]
        linha.notes = "trait: #{a[:trait]}"
        linha.save!
      end
      raise ActiveRecord::Rollback if erros.any?
    end

    if erros.any?
      puts "FALHOU (nada gravado): #{erros.join(' · ')}"
      exit 1
    end

    puts "atrelagens inatas: #{criados} criadas"
    puts "  por tipo: #{SpellSource.where(source_type: %w[Race SubRace]).group(:source_type).count.inspect}"
    puts "  por modo: #{SpellSource.innate.group(:casting_mode).count.inspect}"
    puts "  pools abertos fora: #{pools_abertos.size}"
    puts "  manuais preservadas: #{SpellSource.manual.count}"
  end
end
