# frozen_string_literal: true

# FASE 0 do editor de CLASSES — o mapa das fontes, medido.
#
#   bundle exec rake dnd:audit_class_sources
#
# ⚠️ A regra de uma classe vive em SEIS lugares, e eles não concordam:
#
#   1. `ClassRules::CLASS_RULES` (Ruby, 1766 linhas) — é quem manda hoje
#   2. `klasses.rules` (jsonb) — REPLACE-ALL quando presente; 0 de 13 preenchidas
#   3. colunas de `klasses` — mesmo fato, outra grafia
#   4. `config/class_overrides.yml`
#   5. `config/subclass_overrides.yml` (5931 linhas)
#   6. `sub_klasses.levels_json` (TEXT)
#
# Este rake NÃO conserta nada e NÃO derruba deploy. Ele MEDE, para a fase 1
# saber o que reconciliar. O que está errado aqui é decisão do mestre.
namespace :dnd do
  desc 'FASE 0 — mapeia as fontes de regra de classe e onde elas discordam'
  # Normaliza as duas grafias ao MESMO símbolo, para separar "valor diferente"
  # de "mesma coisa escrita de outro jeito".
  SIGLA = {
    'forca' => 'FOR', 'for' => 'FOR', 'str' => 'FOR',
    'destreza' => 'DES', 'des' => 'DES', 'dex' => 'DES',
    'constituicao' => 'CON', 'con' => 'CON',
    'inteligencia' => 'INT', 'int' => 'INT',
    'sabedoria' => 'SAB', 'sab' => 'SAB', 'wis' => 'SAB',
    'carisma' => 'CAR', 'car' => 'CAR', 'cha' => 'CAR'
  }.freeze

  task audit_class_sources: :environment do
    achados = []
    poe = ->(tipo, quem, texto) { achados << { tipo: tipo, quem: quem, texto: texto } }

    klasses = Klass.order(:api_index).to_a

    # ── 1. o PORTÃO de nível da sub-classe ───────────────────────────────────
    # ⚠️ `SheetKlass#subclass_only_after_threshold` faz `return if
    # threshold.blank?`, e `CharacterProvisioningService` faz
    # `k.try(:subclass_level).to_i` → 0 → `eligible_at_l1` sempre verdadeiro.
    # Com a coluna vazia, os TRÊS guardas do servidor ficam inertes e quem
    # segura a regra é o front — que tem mapa próprio e não conhece classe
    # criada pelo editor.
    klasses.each do |k|
      regra = ClassRules.find(k.api_index)&.dig(:subclass, :choose_level).to_i
      next if regra <= 1

      coluna = k.subclass_level
      if coluna.blank?
        poe.call('portao_inerte', k.api_index,
                 "a regra diz que a sub-classe é escolhida no nível #{regra}, e `klasses.subclass_level` está VAZIA — " \
                 'a validação do model e o guarda do provisionamento não disparam')
      elsif coluna.to_i != regra
        poe.call('coluna_x_regra', k.api_index,
                 "`subclass_level` da coluna é #{coluna} e a regra diz #{regra}")
      end
    end

    # ── 2. coluna × regra nos campos duplicados ──────────────────────────────
    klasses.each do |k|
      r = ClassRules.find(k.api_index)
      next if r.nil?

      hd_col = k.hit_die.to_i
      hd_reg = r[:hit_die].to_s.delete('d').to_i
      if hd_col.positive? && hd_reg.positive? && hd_col != hd_reg
        poe.call('coluna_x_regra', k.api_index, "dado de vida: coluna d#{hd_col}, regra d#{hd_reg}")
      end

      # ⚠️ Grafia, não valor — e MEDIDO: `SavingThrowsCatalog.translate_array`
      # só mapeia sigla EN→PT (`str`→`FOR`). Ele NÃO atravessa
      # `FOR` ↔ `Força`, então a coluna e a regra são duas grafias do mesmo
      # fato sem tradutor entre elas. É o padrão das quatro grafias de
      # proficiência: falta um escritor canônico.
      col = Array(k.saving_throws).map { |v| SIGLA[v.to_s.parameterize] || v.to_s.parameterize }.sort
      reg = Array(SavingThrowsCatalog.translate_array(r[:saving_throws]))
            .map { |v| SIGLA[v.to_s.parameterize] || v.to_s.parameterize }.sort
      if col.any? && reg.any? && col != reg
        poe.call('saving_throws_divergente', k.api_index,
                 "coluna #{Array(k.saving_throws).inspect} × regra #{Array(r[:saving_throws]).inspect} — " \
                 'mesmo depois de normalizar, os valores diferem')
      elsif col.any? && reg.any? && Array(k.saving_throws).map(&:to_s).sort != Array(r[:saving_throws]).map(&:to_s).sort
        poe.call('saving_throws_grafia', k.api_index,
                 "mesmo valor em grafias diferentes: coluna #{Array(k.saving_throws).inspect}, " \
                 "regra #{Array(r[:saving_throws]).inspect} — nenhum tradutor cobre esta direção")
      end
    end

    # ── 3. `klasses.rules` sem validação ─────────────────────────────────────
    # ⚠️ O controller admite `rules: {}` no permit — forma livre — e
    # `KlassDbRulesContract` tem ZERO chamadas no caminho de escrita. Como
    # `ClassRules.find` devolve o DB INTEIRO quando presente, um `rules`
    # incompleto apaga o resto da classe em silêncio.
    com_rules = klasses.select { |k| k.read_attribute(:rules).present? }
    com_rules.each do |k|
      faltam = KlassDbRulesContract.missing_required(k.read_attribute(:rules))
      next if faltam.empty?

      poe.call('rules_incompleto', k.api_index,
               "`klasses.rules` está preenchido e faltam as chaves obrigatórias #{faltam.inspect} — " \
               'como a leitura é replace-all, o resto da classe desaparece')
    end

    # ── 4. sub-classe sem tabela de níveis ───────────────────────────────────
    SubKlass.includes(:klass).order(:api_index).each do |s|
      next if s.levels_json.present?

      poe.call('subclasse_sem_niveis', "#{s.klass&.api_index}/#{s.api_index}",
               "#{s.name.inspect} não tem `levels_json` — o jogador não vê feature nenhuma dela")
    end

    # ── 5. o MESMO sub-classe em dois espaços de slug ────────────────────────
    # ⚠️ Medido: as 11 entradas que não casam por slug EXISTEM no banco com o
    # slug inglês do SRD, e todas com `levels_json` preenchido —
    # `caminho-do-furioso` (YAML) é `berserker` (banco), `colegio-do-conhecimento`
    # é `lore`, `cacador` é `hunter`.
    #
    # Ou seja: não falta conteúdo. O que há é a MESMA sub-classe descrita em
    # dois ficheiros sob dois nomes, e nenhuma tabela de alias
    # (`SubklassSlugResolver`, `DndImportHelpers::SUBCLASS_ALIASES`) cobre esses
    # 11. A armadilha é para quem editar: mexer na cópia do YAML não tem efeito
    # nenhum, porque quem manda é o `levels_json` do banco.
    sem_acento = ->(v) { v.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.strip }
    caminho = Rails.root.join('config', 'subclass_overrides.yml')
    if File.exist?(caminho)
      yml = YAML.load_file(caminho) || {}
      por_classe = SubKlass.includes(:klass).group_by { |s| s.klass&.api_index }
      yml.each do |slug_classe, subs|
        next unless subs.is_a?(Hash)

        existentes = Array(por_classe[slug_classe.to_s]).map { |s| s.api_index.to_s }
        subs.each do |slug_sub, corpo|
          # ⚠️ Nem toda chave sob a classe é sub-classe: `warlock` tem `rules`,
          # `boons` e `invocations`, que são estrutura. O que distingue, medido:
          # a sub-classe de verdade traz `levels`.
          next unless corpo.is_a?(Hash) && corpo.key?('levels')

          bruto = slug_sub.to_s
          alvo = (SubklassSlugResolver::SLUG[bruto] || bruto).to_s
          next if existentes.include?(bruto) || existentes.include?(alvo)

          # ⚠️ Casa por NOME antes de acusar: é assim que se descobre que o
          # "órfão" é na verdade a MESMA sub-classe com o slug do SRD.
          nome = corpo['name'].to_s
          gemea = Array(por_classe[slug_classe.to_s])
                  .find { |s2| sem_acento.call(s2.name) == sem_acento.call(nome) }

          if gemea
            poe.call('duplicado_por_slug', "#{slug_classe}/#{bruto}",
                     "é a mesma sub-classe que #{gemea.api_index.inspect} no banco (#{nome.inspect}) — " \
                     'dois espaços de slug, nenhum alias os liga, e quem manda é o `levels_json`: ' \
                     'editar a cópia do YAML não tem efeito nenhum')
          else
            poe.call('override_sem_destino', "#{slug_classe}/#{bruto}",
                     'está em `subclass_overrides.yml` e não existe no banco, nem por slug nem por ' \
                     'nome — o override nunca se aplica')
          end
        end
      end
    end

    # ── relatório ────────────────────────────────────────────────────────────
    puts "== fontes medidas\n"
    puts "  classes: #{klasses.size}  ·  com `klasses.rules` preenchido: #{com_rules.size}"
    puts "  sub-classes: #{SubKlass.count}  ·  com `levels_json`: #{SubKlass.where.not(levels_json: nil).count}"
    puts "  ClassRules::CLASS_RULES (Ruby): #{ClassRules::CLASS_RULES.size} classes\n\n"

    puts "== achados: #{achados.size}\n\n"
    if achados.empty?
      puts '  ✓ nenhum — as fontes concordam'
    else
      achados.group_by { |a| a[:tipo] }.each do |tipo, lista|
        puts "  [#{tipo}]  #{lista.size}"
        lista.each { |a| puts "     ⚠️ #{a[:quem]}: #{a[:texto]}" }
        puts
      end
      puts '  Este rake MEDE. A reconciliação é a fase 1 do plano.'
    end
  end
end
