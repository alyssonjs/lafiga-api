# frozen_string_literal: true

# Índice REVERSO: quem concede cada proficiência.
#
#   bundle exec rake dnd:seed_proficiency_sources            # aplica
#   DRY_RUN=1 bundle exec rake dnd:seed_proficiency_sources  # só relata
#
# ⚠️ É REGISTRO, não autoridade. Quem concede continua a ser `race_rules.yml`,
# `class_rules.rb`, `background_rules.rb` e a coluna do `Feat` — esta tabela só
# torna visível o que já acontece. Marcar uma fonte aqui não faz ninguém ganhar
# a proficiência.
#
# ⚠️ Só toca em `origin: 'derived'`. O que o mestre associou à mão (`manual`)
# sobrevive a qualquer re-semeadura — re-derivar não pode apagar o trabalho
# dele, e é o tipo de perda que ninguém repara até fazer falta.
namespace :dnd do
  desc 'Deriva quem concede cada proficiência, das fontes que já existem'
  task seed_proficiency_sources: :environment do
    require 'yaml'
    seco = ENV['DRY_RUN'].present?
    achados = {}   # [prof_id, tipo, chave] => nome
    nao_resolvidos = Hash.new(0)

    # ⚠️ `modo` é FIXA ou ESCOLHA, e a distinção não é cosmética: "Raça: Anão"
    # em Ferramentas de ferreiro lê como se todo anão a tivesse, quando o anão
    # escolhe UMA entre três. Medido: 144 das associações vêm de pool.
    registra = lambda do |valor, tipo, chave, nome, modo = 'fixed', quantas = nil|
      next if valor.blank? || !valor.is_a?(String)

      p = Proficiency.resolve(valor)
      if p.nil?
        nao_resolvidos[valor] += 1
        next
      end
      # A primeira gravação vence: se a mesma fonte concede a mesma
      # proficiência de dois jeitos, FIXA é a mais forte e vem primeiro nos
      # laços abaixo.
      achados[[p.id, tipo, chave.to_s]] ||= { nome: nome.to_s, modo: modo, quantas: quantas }
    end

    # ── RAÇA e SUB-RAÇA ────────────────────────────────────────────────────
    yaml = YAML.load_file(Rails.root.join('config', 'race_rules.yml'))
    anda = lambda do |no, tipo, chave_pai|
      next unless no.is_a?(Hash)

      chave = no['id'] || chave_pai
      nome = no['name'] || chave
      pr = no['proficiencies']
      if pr.is_a?(Hash)
        %w[weapons armor].each { |c| Array(pr[c]).each { |v| registra.call(v, tipo, chave, nome) } }
        %w[tools skills].each do |c|
          bloco = pr[c]
          if bloco.is_a?(Hash)
            Array(bloco['fixed']).each { |v| registra.call(v, tipo, chave, nome) }
            quantas = bloco['choiceCount'] || bloco['choose']
            Array(bloco['choices']).each { |v| registra.call(v, tipo, chave, nome, 'choice', quantas) }
          else
            Array(bloco).each { |v| registra.call(v, tipo, chave, nome) }
          end
        end
      end
      Array(no.dig('languages', 'always')).each { |v| registra.call(v, tipo, chave, nome) }
      (no['subraces'] || {}).each_value { |sr| anda.call(sr, 'sub_race', chave) } if no['subraces'].is_a?(Hash)
    end
    yaml.each { |chave, r| anda.call(r.is_a?(Hash) ? r.merge('id' => r['id'] || chave) : r, 'race', chave) } if yaml.is_a?(Hash)

    # ── CLASSE ─────────────────────────────────────────────────────────────
    # `ClassRules.find` prefere o banco (`klasses.rules`) ao hash em código —
    # é o que de facto se aplica, e por isso é o acessor certo aqui.
    Klass.find_each do |k|
      regra = ClassRules.find(k.api_index)
      next unless regra

      %i[weapon_proficiencies armor_proficiencies saving_throws].each do |campo|
        Array(regra[campo]).each { |v| registra.call(v, 'klass', k.api_index, k.name) }
      end
      # PERÍCIAS da classe: quase sempre um pool.
      #
      # ⚠️ `options: :any` (Bardo escolhe 3 entre TODAS) fica de FORA. Criar 18
      # associações ali diria "Bardo concede Acrobacia", o que engana: o Bardo
      # não concede perícia nenhuma em particular. Um pool aberto não é uma
      # associação com uma proficiência específica.
      sp = regra[:skill_proficiencies]
      if sp.is_a?(Hash)
        opcoes = sp['options'] || sp[:options]
        quantas = sp['choose'] || sp[:choose]
        if opcoes.is_a?(Array)
          opcoes.each { |v| registra.call(v, 'klass', k.api_index, k.name, 'choice', quantas) }
        end
      end

      tp = regra[:tool_proficiencies]
      (tp.is_a?(Array) ? tp : [tp]).compact.each do |t|
        if t.is_a?(String)
          registra.call(t, 'klass', k.api_index, k.name)
        elsif t.is_a?(Hash)
          # Forma `{ 'instruments' => { choose: N, choices: [...] } }` e também
          # a plana `{ fixed:, choices: }`.
          Array(t[:fixed] || t['fixed']).each { |v| registra.call(v, 'klass', k.api_index, k.name) }
          quantas_t = t['choose'] || t[:choose]
          Array(t['choices'] || t[:choices]).each { |v| registra.call(v, 'klass', k.api_index, k.name, 'choice', quantas_t) }
          t.each_value do |sub|
            next unless sub.is_a?(Hash)

            q = sub['choose'] || sub[:choose]
            Array(sub['choices'] || sub[:choices]).each { |v| registra.call(v, 'klass', k.api_index, k.name, 'choice', q) }
            Array(sub['fixed'] || sub[:fixed]).each { |v| registra.call(v, 'klass', k.api_index, k.name) }
          end
        end
      end
    end

    # ── ANTECEDENTE ────────────────────────────────────────────────────────
    BackgroundRules::RULES.each do |chave, bg|
      nome = bg[:name] || chave
      Array(bg[:skills]).each { |v| registra.call(v, 'background', chave, nome) }
      Array(bg[:tools]).each do |t|
        if t.is_a?(String)
          registra.call(t, 'background', chave, nome)
        elsif t.is_a?(Hash)
          t.each_value do |sub|
            next unless sub.is_a?(Hash)

            q = sub[:choose] || sub['choose']
            Array(sub[:choices] || sub['choices']).each { |c| registra.call(c, 'background', chave, nome, 'choice', q) }
          end
        end
      end
      l = bg[:languages]
      if l.is_a?(Hash)
        q = l[:choose] || l['choose']
        Array(l[:choices] || l['choices']).each { |v| registra.call(v, 'background', chave, nome, 'choice', q) }
      end
    end

    # ── TALENTO ────────────────────────────────────────────────────────────
    Feat.find_each do |f|
      bruto = f.proficiency_bonuses
      next if bruto.blank?

      h = begin
        bruto.is_a?(String) ? JSON.parse(bruto) : bruto
      rescue JSON::ParserError
        nil
      end
      next unless h.is_a?(Hash)

      h.each_value { |v| Array(v).each { |x| registra.call(x, 'feat', f.api_index, f.name) } }
    end

    if seco
      por_tipo = achados.keys.group_by { |(_, tipo, _)| tipo }.transform_values(&:size)
      por_modo = achados.values.group_by { |d| d[:modo] }.transform_values(&:size)
      puts "[DRY RUN] #{achados.size} associações derivadas: #{por_tipo.sort.to_h.inspect}"
      puts "          por modo: #{por_modo.inspect}"
      puts "não resolvidos: #{nao_resolvidos.size}"
      nao_resolvidos.first(8).each { |v, n| puts "    #{v.inspect} (#{n}x)" }
      next
    end

    criados = 0
    ActiveRecord::Base.transaction do
      achados.each do |(prof_id, tipo, chave), dados|
        linha = ProficiencySource.find_or_initialize_by(
          proficiency_id: prof_id, source_type: tipo, source_key: chave
        )
        criados += 1 if linha.new_record?
        # ⚠️ NÃO rebaixa para `derived` o que o mestre marcou como `manual`,
        # nem sobrescreve o modo que ele escolheu.
        if linha.new_record? || linha.origin == 'derived'
          linha.origin = 'derived'
          linha.grant_mode = dados[:modo]
          linha.choose_count = dados[:modo] == 'choice' ? dados[:quantas] : nil
        end
        linha.source_name = dados[:nome]
        linha.save!
      end

      # Poda o que era derivado e já não é — sem tocar no manual.
      vivos = achados.keys.map { |(pid, t, k)| [pid, t, k] }.to_set
      podados = 0
      ProficiencySource.derived.find_each do |linha|
        next if vivos.include?([linha.proficiency_id, linha.source_type, linha.source_key])

        linha.destroy
        podados += 1
      end
      puts "podadas (derivadas que já não valem): #{podados}"
    end

    puts "associações: #{criados} criadas, #{ProficiencySource.count} no total"
    puts "  por tipo: #{ProficiencySource.group(:source_type).count.sort.to_h.inspect}"
    puts "  por modo: #{ProficiencySource.group(:grant_mode).count.inspect}"
    puts "  manuais preservadas: #{ProficiencySource.manual.count}"
    puts "não resolvidos: #{nao_resolvidos.size}" if nao_resolvidos.any?
  end
end
