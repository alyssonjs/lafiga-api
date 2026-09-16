# frozen_string_literal: true

namespace :dnd do
  # Projeta `rules.subclass.choose_level` na coluna `klasses.subclass_level`.
  #
  # ⚠️ A coluna está VAZIA nas 13 classes, e é isso que mantém SETE guardas do
  # servidor inertes — todos fazem `k.try(:subclass_level).to_i`, que com NULL dá
  # 0 e passa sempre: a validação do model (`SheetKlass#subclass_only_after_threshold`
  # faz `return if threshold.blank?`), o `LevelUpGuardService`, o
  # `CharacterProvisioningService`, o `RandomCharacterGenerator` (dois pontos) e
  # duas rakes de auditoria. Com eles dormindo, quem segura a regra é o FRONT —
  # que tem mapa próprio (`SUBCLASS_LEVELS`) e não conhece classe criada pelo
  # editor do compêndio.
  #
  # Medido em 16/09/2026 antes de acordar: 63 fichas com sub-classe, ZERO ilegais
  # pela regra e ZERO fichas já no nível de escolher sem sub-classe escolhida.
  #
  #   bundle exec rails dnd:backfill_subclass_level           # relatório
  #   bundle exec rails dnd:backfill_subclass_level APPLY=1   # grava
  desc 'Projeta rules.subclass.choose_level na coluna klasses.subclass_level (APPLY=1 grava)'
  task backfill_subclass_level: :environment do
    aplicar = ENV['APPLY'] == '1'
    puts "== dnd:backfill_subclass_level (#{aplicar ? 'APLICANDO' : 'simulação — use APPLY=1'})"

    alvo = {}
    sem_regra = []
    Klass.order(:api_index).find_each do |k|
      regra = ClassRules.find(k.api_index)
      nivel = (regra&.dig(:subclass, :choose_level) || regra&.dig('subclass', 'choose_level')).to_i
      nivel.positive? ? alvo[k.id] = nivel : sem_regra << k.api_index
    end

    # ⚠️ Preencher a coluna ACORDA os guardas. Antes de gravar, medir o que eles
    # passariam a recusar: uma ficha com sub-classe abaixo do nível deixaria de
    # validar, e o jogador ficaria sem conseguir gravar a própria personagem.
    ilegais = SheetKlass.where.not(sub_klass_id: nil).includes(:klass, :sheet).select do |sk|
      limite = alvo[sk.klass_id].to_i
      limite.positive? && sk.level.to_i < limite
    end

    if ilegais.any?
      puts "⚠️ #{ilegais.size} ficha(s) ficariam ILEGAIS com os guardas acordados:"
      ilegais.first(20).each do |sk|
        puts "   sheet #{sk.sheet_id} · #{sk.klass&.api_index} nv#{sk.level} < #{alvo[sk.klass_id]}"
      end
      unless ENV['FORCE'] == '1'
        abort '== abortado: resolva essas fichas primeiro (ou rode com FORCE=1, ciente do que bloqueia)'
      end
      puts '== FORCE=1: seguindo mesmo assim'
    else
      puts '== 0 fichas ficariam ilegais ✓'
    end

    mudadas = 0
    Klass.order(:api_index).find_each do |k|
      regra = ClassRules.find(k.api_index) || {}
      colunas = {}

      nivel = alvo[k.id]
      colunas[:subclass_level] = nivel if nivel && k.subclass_level.to_i != nivel

      # ⚠️ `saving_throws` é a MESMA projeção, e é a origem dos 13 achados de
      # `saving_throws_grafia`: a coluna guarda "Força" e a regra guarda "FOR" —
      # o mesmo fato em duas grafias, sem tradutor entre elas
      # (`SavingThrowsCatalog` só cobre EN→PT de sigla). Medido: a coluna não
      # tem LEITOR nenhum (`build_saving_throws` lê a regra), então alinhá-la à
      # regra não muda ficha alguma — só para de mentir.
      da_regra = Array(regra[:saving_throws] || regra['saving_throws']).map(&:to_s)
      colunas[:saving_throws] = da_regra if da_regra.any? && Array(k.saving_throws).map(&:to_s) != da_regra

      next if colunas.empty?

      puts format('   %-16s %s', k.api_index, colunas.map { |c, v| "#{c}: #{k[c].inspect} → #{v.inspect}" }.join('  ·  '))
      mudadas += 1
      # `update_columns`: é PROJEÇÃO de uma regra já validada, não edição — não
      # faz sentido disparar validação nem callback de classe por causa dela.
      k.update_columns(colunas) if aplicar
    end

    puts "== #{mudadas} classe(s) #{aplicar ? 'atualizada(s)' : 'a atualizar'}"
    puts "== sem `choose_level` na regra (coluna intocada): #{sem_regra.inspect}" if sem_regra.any?
    puts '== nada gravado (rode com APPLY=1)' unless aplicar
  end
end
