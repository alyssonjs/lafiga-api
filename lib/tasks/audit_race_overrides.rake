# frozen_string_literal: true

# FASE 3 do editor de raças — o que o mestre GRAVOU chega mesmo à ficha?
#
#   bundle exec rake dnd:audit_race_overrides
#
# O overlay (`rules_json`) atravessa quatro camadas até virar regra na ficha:
# `load_overlay` → `aplicar_overlay` → `RaceRules.apply` → `RaceProducer`. Cada
# uma tem um ponto onde a regra do mestre desaparece **sem erro**:
#
#   · `load_overlay` faz `next if r.api_index.blank?` — overlay sem chave nunca
#     é lido;
#   · `aplicar_overlay` faz `next if raca.nil?` — sub-raça cuja raça não existe
#     no bundle é descartada inteira;
#   · o trait ref com `key` que ninguém define não vira nada;
#   · e `RaceProducer#interpolate` resolve `<damage>` a partir do REF: sem o
#     campo no ref, o valor vira string vazia e é descartado — a resistência
#     do Draconato some e a ficha não diz porquê.
#
# ⚠️ Este rake NÃO conserta nada e não derruba deploy. Ele MEDE. Divergência
# aqui é decisão do mestre (qual das duas leituras está certa), e o portão da
# fase é: zero achados no catálogo de hoje.
namespace :dnd do
  desc 'FASE 3 — confere se o overlay de raças chega mesmo à ficha'
  task audit_race_overrides: :environment do
    achados = []
    def achados.poe(tipo, quem, texto)
      self << { tipo: tipo, quem: quem, texto: texto }
    end

    bundle = RaceRules.bundle
    defs = bundle[:trait_definitions] || {}
    racas = bundle[:races] || {}

    # ── 1. overlay que nunca é LIDO ──────────────────────────────────────────
    # `load_overlay` exige `api_index`. Sem ele, o mestre grava, a tela mostra
    # o valor de volta (vem do próprio registo) e a ficha nunca muda.
    Race.where.not(rules_json: {}).find_each do |r|
      achados.poe('overlay_sem_chave', "Race##{r.id} #{r.name}",
                  'tem `rules_json` mas `api_index` vazio — `load_overlay` ignora, e a regra nunca chega à ficha') if r.api_index.blank?
    end

    SubRace.where.not(rules_json: {}).includes(:race).find_each do |sr|
      quem = "SubRace##{sr.id} #{sr.name}"
      if sr.api_index.blank?
        achados.poe('overlay_sem_chave', quem, 'tem `rules_json` mas `api_index` vazio — nunca é lido')
        next
      end
      if sr.race&.api_index.blank?
        achados.poe('overlay_sem_chave', quem, "a raça (#{sr.race&.name.inspect}) não tem `api_index` — o overlay da sub-raça é descartado com ela")
        next
      end

      # ── 2. sub-raça cuja RAÇA não existe no bundle ──
      # `aplicar_overlay` faz `next if raca.nil?`: sem nó de raça (nem no YAML
      # nem no overlay), tudo o que o mestre escreveu na sub-raça é largado.
      chave = sr.race.api_index.to_s
      unless racas.key?(chave.to_sym) || racas.key?(chave)
        achados.poe('overlay_nao_aplicado', quem,
                    "a raça #{chave.inspect} não existe no catálogo — `aplicar_overlay` descarta o overlay da sub-raça inteiro")
      end
    end

    # ── 3. forma que o SANITIZADOR recusaria ─────────────────────────────────
    # ⚠️ Reusa o escritor canônico em vez de reimplementar a validação: duas
    # listas de regras divergem, e a que fica velha é sempre a de leitura.
    # Linhas escritas por console ou rake não passaram por ele.
    [[Race, 'Race'], [SubRace, 'SubRace']].each do |classe, rotulo|
      classe.where.not(rules_json: {}).find_each do |linha|
        _limpo, erros = Races::RulesOverlay.sanitize(linha.rules_json)
        next if erros.empty?

        achados.poe('forma_invalida', "#{rotulo}##{linha.id} #{linha.name}", erros.join('; '))
      end
    end

    # ── 4 e 5. traços: ref sem definição, e definição sem ref ────────────────
    nos = []
    racas.each do |slug, r|
      nos << [slug.to_s, r]
      (r[:subraces] || {}).each { |s, sr| nos << ["#{slug}/#{s}", sr] }
    end

    referenciados = []
    donos = Hash.new { |h, k| h[k] = [] }
    nos.each do |quem, no|
      Array(no[:traits]).each do |t|
        ref = t.is_a?(Hash) ? t : { key: t.to_s }
        chave = ref[:key].to_s
        next if chave.empty?

        referenciados << chave
        donos[chave] << quem
        definicao = defs[chave.to_sym] || defs[chave]
        if definicao.nil?
          achados.poe('traco_sem_definicao', quem,
                      "o traço #{chave.inspect} não existe no catálogo — a ficha fica sem ele, em silêncio")
          next
        end

        # ── 6. placeholder sem o campo no REF ──
        # `RaceProducer#interpolate` tira `<damage>` do ref. Sem o campo, o
        # valor vira "" e é descartado: o grant evapora.
        faltando = placeholders_de(definicao).reject { |campo| ref[campo.to_sym].present? || ref[campo].present? }
        next if faltando.empty?

        achados.poe('placeholder_sem_campo', quem,
                    "#{chave} usa #{faltando.map { |f| "<#{f}>" }.join(', ')} nos grants e o ref não traz #{faltando.join(', ')} — o grant vira vazio e some")
      end
    end

    # Traço PRÓPRIO definido e nunca referenciado = trabalho invisível. Só vale
    # para os do overlay: o catálogo do YAML tem definições partilhadas de
    # propósito, e apontá-las seria ruído.
    overlay = RaceRules.overlay || {}
    (overlay[:trait_definitions] || {}).each_key do |chave|
      next if referenciados.include?(chave.to_s)

      achados.poe('traco_proprio_sem_ref', chave.to_s,
                  'é definido como traço próprio e nenhuma raça o referencia — não aparece em ficha nenhuma')
    end

    # ── 7. definição que NINGUÉM referencia ──────────────────────────────────
    # ⚠️ Separada de propósito: uma definição órfã não chega a ficha nenhuma,
    # então o que quer que esteja errado nela é entrada morta no catálogo, não
    # regra quebrada na mesa. Misturar as duas faz o mestre procurar um
    # problema de jogo onde há arrumação.
    orfas = defs.keys.map(&:to_s) - referenciados.uniq
    orfas.each do |chave|
      achados.poe('definicao_orfa', chave,
                  'está no catálogo de traços e nenhuma raça o referencia — não chega a ficha nenhuma')
    end

    # ── 8. a PROSA promete resistência que o DADO não concede ────────────────
    # O mesmo padrão do `dnd:audit_innate_grants`, aplicado às defesas.
    #
    # ⚠️ Só para os traços REFERENCIADOS. Apontar a prosa de uma definição órfã
    # seria contar o mesmo achado duas vezes — foi o erro que o
    # `audit_innate_grants` cometeu e que fez o relatório inventar problemas.
    defs.each do |chave, definicao|
      next if orfas.include?(chave.to_s)

      prosa = (definicao[:description] || definicao['description']).to_s
      next if prosa.empty?

      g = definicao[:grants] || {}
      concedidos = %i[resistance immunity].flat_map { |k| Array((g[:defenses] || {})[k]) }
                                          .map { |v| v.to_s.downcase }
      # Placeholder na prosa (`<dano>`) é a ancestralidade a ser preenchida
      # pelo ref, não uma promessa concreta.
      next if prosa.match?(/<[^<>\s]+>/)
      next unless prosa.match?(/resist[êe]ncia|imunidade|imune/i)

      prometidos = Combat::DamageMitigationRules::DAMAGE_TYPE_NORMALIZE.keys.select do |tipo|
        prosa.downcase.include?(tipo)
      end.map { |t| Combat::DamageMitigationRules::DAMAGE_TYPE_NORMALIZE[t] }.uniq

      nao_concedidos = prometidos.reject do |p|
        concedidos.any? { |c| Combat::DamageMitigationRules::DAMAGE_TYPE_NORMALIZE[c] == p || c == p }
      end
      next if nao_concedidos.empty?

      quem = donos[chave.to_s]
      achados.poe('prosa_x_dado', "#{chave} (#{quem.join(', ')})",
                  "a prosa fala em #{nao_concedidos.join(', ')} e os grants não concedem — a mesa lê uma regra que o código não aplica")
    end

    # ── relatório ────────────────────────────────────────────────────────────
    puts "== overlays no banco: #{Race.where.not(rules_json: {}).count} raças, " \
         "#{SubRace.where.not(rules_json: {}).count} sub-raças"
    puts "== nós no catálogo: #{nos.size} · definições de traço: #{defs.size}\n\n"

    puts "== achados: #{achados.size}\n\n"
    if achados.empty?
      puts '  ✓ nenhum — tudo o que está gravado chega à ficha'
    else
      achados.group_by { |a| a[:tipo] }.each do |tipo, lista|
        puts "  [#{tipo}]  #{lista.size}"
        lista.each { |a| puts "     ⚠️ #{a[:quem]}: #{a[:texto]}" }
        puts
      end
      puts '  Decisão é do mestre. Este rake NÃO conserta e NÃO derruba deploy.'
    end
  end

  # Campos `<assim>` usados dentro dos grants de uma definição.
  def placeholders_de(definicao)
    (definicao[:grants] || definicao['grants'] || {}).to_s.scan(/<([^<>\s]+)>/).flatten.uniq
  end
end
