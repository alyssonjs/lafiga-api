# frozen_string_literal: true

namespace :dnd do
  # Repõe o `class_summary` das fichas depois de uma edição de classe ou
  # sub-classe. Idempotente.
  #
  # ⚠️ `ALL=1` é obrigatório para varrer tudo. Sem essa trava, um engano de
  # digitação em `KLASS=` viraria "reprocessar todas as fichas do jogo", e a
  # diferença entre um resync certo e um resync largo demais só aparece depois.
  #
  #   bundle exec rails dnd:resync_class_summaries KLASS=fighter DRY_RUN=1
  #   bundle exec rails dnd:resync_class_summaries KLASS=fighter
  #   bundle exec rails dnd:resync_class_summaries SUB=mestre-de-batalha
  #   bundle exec rails dnd:resync_class_summaries ALL=1 DRY_RUN=1
  desc 'Repõe class_summary das fichas (KLASS= | SUB= | ALL=1; DRY_RUN=1 mede sem gravar)'
  task resync_class_summaries: :environment do
    seco = ENV['DRY_RUN'] == '1'
    klass = resolve_klass(ENV.fetch('KLASS', nil))
    sub = resolve_sub(ENV.fetch('SUB', nil))

    if klass.nil? && sub.nil? && ENV['ALL'] != '1'
      abort '== defina KLASS=, SUB= ou ALL=1 — varrer todas as fichas tem de ser um pedido explícito'
    end

    puts "== dnd:resync_class_summaries (#{seco ? 'simulação' : 'APLICANDO'})" \
         "#{klass ? " klass=#{klass.api_index}" : ''}#{sub ? " sub=#{sub.api_index}" : ''}"

    r = Klasses::ResyncSummaries.call(klass_id: klass&.id, sub_klass_id: sub&.id, dry_run: seco)

    puts "== #{r.mudadas} de #{r.vistas} ficha(s) #{seco ? 'mudariam' : 'repostas'}"

    perdas = r.detalhes.select { |d| d[:removidos].present? }
    if perdas.any?
      puts "⚠️ #{perdas.size} ficha(s) perderiam escolha do jogador (a regra deixou de oferecer):"
      perdas.first(20).each { |d| puts "   sheet #{d[:sheet_id]} · #{d[:campo]}: #{d[:removidos].inspect}" }
    end

    r.detalhes.reject { |d| d[:removidos].present? }.first(15).each do |d|
      puts "   sheet #{d[:sheet_id]}: #{Array(d[:mudou]).inspect}"
    end
    puts '== nada gravado (rode sem DRY_RUN=1)' if seco
  end

  def resolve_klass(valor)
    return nil if valor.blank?

    achada = Klass.find_by(api_index: valor) || (valor.match?(/\A\d+\z/) ? Klass.find_by(id: valor) : nil)
    abort "== classe não encontrada: #{valor.inspect}" if achada.nil?
    achada
  end

  def resolve_sub(valor)
    return nil if valor.blank?

    achada = SubKlass.find_by(api_index: valor) || (valor.match?(/\A\d+\z/) ? SubKlass.find_by(id: valor) : nil)
    abort "== sub-classe não encontrada: #{valor.inspect}" if achada.nil?
    achada
  end
end
