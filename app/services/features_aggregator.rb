require 'set'
require 'yaml'

class FeaturesAggregator
  # Padrões de NOME que identificam placeholders genéricos de slot de
  # subclasse (features de CLASSE que só existem para marcar "aqui entra um
  # recurso da sua subclasse"). Quando o nível já tem uma feature REAL de
  # subclasse, estes placeholders viram ruído e são ocultados (R7).
  #
  # Ex.: Bruxo L1 "Patrono de Outro Mundo", Guerreiro L7 "Recurso de
  # arquétipo marcial", Bárbaro L6 "Recurso de caminho", Bardo L6 "Recurso da
  # faculdade de bardo", Paladino L7 "Recurso de juramento sagrado".
  PLACEHOLDER_NAME_PATTERNS = [
    /\Arecurso (de|da|do) /i,
    /patrono de outro mundo/i,
    /\Aarqu[eé]tipo marcial\z/i,
    /\Aarqu[eé]tipo ladino\z/i,
    /\Acaminho primal\z/i,
    /\Afaculdade de bardo\z/i,
    /\Ajuramento sagrado\z/i
  ].freeze

  # `api_index` dos placeholders de slot de subclasse. Mais robusto que o nome
  # (independe de tradução): o slot canônico (`otherworldly-patron`,
  # `martial-archetype`, …) e seus "-improvement-N".
  PLACEHOLDER_API_PATTERNS = [
    /\A(otherworldly-patron|martial-archetype|roguish-archetype|primal-path|bard-college|sacred-oath|monastic-tradition|divine-domain|druid-circle|sorcerous-origin|ranger-archetype|sorcerous-archetype)(-improvement-\d+)?\z/i,
    /-improvement-\d+\z/i
  ].freeze

  def initialize(sheet, sync: true)
    @sheet = sheet
    @sync = sync
  end

  def call
    sync_characters_features! if @sync
    char = @sheet.character
    show_map = CharactersFeature.where(character_id: char.id).pluck(:feature_id, :id, :show).each_with_object({}) do |(fid, id, show), h|
      h[fid] = { id: id, show: (show != false) }
    end
    items = []
    @sheet.sheet_klasses.each do |sk|
      klass = sk.klass
      next unless klass
      ClassLevel.includes(:features).where(klass_id: klass.id).where('level <= ?', sk.level.to_i).each do |cl|
        cl.features.each do |f|
          items << build_item(f, cl.level, 'Klass', show_map)
        end
      end
      if sk.sub_klass
        # `levels_json` da subclasse: fonte de verdade dos NOMES canônicos
        # (usado para desempatar pares legado×canônico no mesmo nível — R7).
        canon = canonical_names_by_level(sk.sub_klass)
        SubKlassLevel.includes(:features).where(sub_klass_id: sk.sub_klass_id).where('level <= ?', sk.level.to_i).each do |sl|
          sl.features.each do |f|
            item = build_item(f, sl.level, 'SubKlass', show_map)
            item[:canonical] = canon[[sl.level.to_i, normalize_name(f.localized_name)]] || false
            items << item
          end
        end
      end
    end

    # Disciplinas elementais ESCOLHIDAS (Monge Caminho dos Quatro Elementos): as
    # seleções vivem em metadata.class_choices e não têm feature estática; emiti-las
    # como features para que apareçam na ficha (MonkSection renderiza character.features).
    items.concat(subclass_choice_feature_items)

    items = dedup_and_hide_placeholders(items)
    items.sort_by { |x| [x[:level].to_i, x[:name].to_s] }
  end

  private

  # Emite as disciplinas elementais escolhidas pelo Monge (Quatro Elementos) como
  # features. Dedupa por id (a escolha do L6 pode gravar o conjunto cumulativo),
  # atribuindo a cada disciplina o menor nível em que foi escolhida.
  # Emite as SELEÇÕES do picker de subclasse (class_choices) como features, para
  # aparecerem na ficha. Cobre: disciplinas elementais (Quatro Elementos, chave
  # 'discipline', resolvidas via elemental_disciplines.yml) e tatuagens (Monge
  # Tatuado, chave 'tattoo', o próprio nome já é o rótulo — sem catálogo).
  def subclass_choice_feature_items
    items = []
    items.concat(choice_items_for('quatro-elementos', 'discipline', 'discipline', elemental_disciplines_catalog))
    items.concat(choice_items_for('caminho_monge_tatuado', 'tattoo', 'tattoo', {}))
    items.concat(choice_items_for('caminho_punho_sagrado', 'sacred_domain', 'sacred-domain', {}))
    items
  end

  # Dedupa por id (a escolha de níveis superiores pode gravar o conjunto
  # cumulativo), atribuindo a cada seleção o MENOR nível em que foi escolhida.
  def choice_items_for(sub_api_index, choice_key, id_prefix, catalog)
    return [] unless subclass_present?(sub_api_index)
    per_level = (@sheet.metadata || {}).dig('class_choices', 'per_level')
    return [] unless per_level.is_a?(Hash)

    chosen = {} # id => menor nível de escolha
    per_level.each do |lvl, row|
      next unless row.is_a?(Hash)
      # flattenFeatureChoicesToRow (front) grava as escolhas ACHATADAS direto na linha
      # do nível — row['discipline'] / row['tattoo'] / row['sacred_domain'] — e NUNCA
      # sob um wrapper 'feature_choices'. Lê flat (shape de produção), com fallback
      # defensivo ao wrapper aninhado para eventuais metadados legados/fabricados.
      nested = row['feature_choices'] || row[:feature_choices] || {}
      raw = row[choice_key] || row[choice_key.to_sym] || nested[choice_key] || nested[choice_key.to_sym]
      Array(raw).each do |id|
        next if id.to_s.strip.empty?
        l = lvl.to_i
        chosen[id] = l if chosen[id].nil? || l < chosen[id]
      end
    end
    return [] if chosen.empty?

    chosen.map do |id, lvl|
      d = catalog[id.to_s]
      {
        id: "#{id_prefix}-#{id}",
        api_index: id.to_s,
        level: lvl,
        name: d ? d['name_pt'].to_s : id.to_s,
        desc: d ? d['description'].to_s.strip : '',
        source: 'SubKlass',
        show: true,
        pref_id: nil
      }
    end
  end

  def subclass_present?(api_index)
    @sheet.sheet_klasses.any? do |sk|
      sk.sub_klass && sk.sub_klass.api_index.to_s == api_index
    end
  end

  def elemental_disciplines_catalog
    @elemental_disciplines_catalog ||= begin
      path = Rails.root.join('config', 'class_choices', 'elemental_disciplines.yml')
      rows = YAML.load_file(path)
      Array(rows).each_with_object({}) do |r, h|
        h[r['slug'].to_s] = r if r.is_a?(Hash) && r['slug']
      end
    rescue StandardError
      {}
    end
  end

  def build_item(feature, level, source, show_map)
    {
      id: feature.id,
      api_index: feature.api_index,
      level: level,
      name: feature.localized_name,
      desc: feature.localized_description,
      source: source,
      show: (show_map[feature.id]&.dig(:show) != false),
      pref_id: show_map[feature.id]&.dig(:id)
    }
  end

  # R7 — limpeza da lista `features`:
  # 1. Dedup por (nível, nome normalizado): mantém 1 só por slot.
  # 2. Pares legado×canônico (mesmo nível + mesma SubKlass, nomes diferentes):
  #    prefere a canônica (nome casa com levels_json; senão maior id).
  # 3. Placeholders genéricos de classe ocultados quando o nível já tem uma
  #    feature REAL (nomeada, não-placeholder) de subclasse.
  #
  # NUNCA deduplica entre níveis diferentes — ASI/Expertise/Segredos Arcanos
  # repetem legitimamente por nível.
  def dedup_and_hide_placeholders(items)
    # ── Passo 1: dedup exato por (nível, nome normalizado) ────────────
    by_key = {}
    items.each do |it|
      key = [it[:level].to_i, normalize_name(it[:name])]
      existing = by_key[key]
      by_key[key] = existing.nil? ? it : prefer_feature(existing, it)
    end
    deduped = by_key.values

    # Níveis que têm pelo menos uma feature REAL de subclasse (nomeada,
    # não-placeholder). Usado para decidir quando ocultar placeholders.
    levels_with_real_subclass = deduped.each_with_object(Set.new) do |it, set|
      next unless it[:source] == 'SubKlass'
      next if placeholder?(it)
      set << it[:level].to_i
    end

    # ── Passo 3: ocultar placeholders quando há feature real no nível ──
    deduped.each do |it|
      next unless placeholder?(it)
      it[:show] = false if levels_with_real_subclass.include?(it[:level].to_i)
    end

    # ── Passo 2: pares legado×canônico no mesmo nível/origem (SubKlass) ─
    # Mesmo nível + mesma origem SubKlass + nomes DIFERENTES, e ambos
    # parecem o "mesmo slot" (um casa com levels_json e o outro não, OU
    # diferença só de id antigo<novo). Mantemos só a canônica.
    resolve_legacy_canonical_pairs!(deduped)

    # `:canonical` é flag interna de desempate — não vaza no contrato da ficha.
    deduped.each { |it| it.delete(:canonical) }
    deduped
  end

  # Entre duas features com a MESMA chave (nível+nome normalizado), prefere a
  # canônica; em empate, o maior id (registro novo curado). Mantém `show`
  # falso se qualquer cópia estava oculta por preferência do usuário.
  def prefer_feature(a, b)
    winner, loser =
      if a[:canonical] && !b[:canonical]
        [a, b]
      elsif b[:canonical] && !a[:canonical]
        [b, a]
      elsif a[:id].to_i >= b[:id].to_i
        [a, b]
      else
        [b, a]
      end
    # Preserva ocultação explícita do usuário (CharactersFeature.show=false).
    winner[:show] = false if loser[:pref_id] && loser[:show] == false
    winner
  end

  # Stopwords PT-BR que não contam como "palavra de conteúdo" ao comparar se
  # duas features são o MESMO slot renomeado (legado×canônico).
  STOPWORDS = %w[de da do das dos e em a o as os ao aos na no nas nos um uma].freeze

  # Pares legado×canônico no MESMO nível/origem SubKlass. O `levels_json`
  # (curado) é a fonte de verdade dos nomes canônicos; o BD acumulou linhas
  # ANTIGAS (ids menores, vindas de reimportações) que duplicam os mesmos slots
  # com nomes obsoletos. Ocultamos as legadas — mas só quando é SEGURO:
  #
  #  Condição A (1:1 limpo): o nº de features legadas (não-canônicas, id < menor
  #  id canônico do nível) é IGUAL ao nº de features canônicas do nível. Isto
  #  caracteriza uma duplicação completa "set antigo × set novo" (ex.: Bruxo
  #  Corruptor L10 "Resiliência Infernal" × "Resistência Demoníaca" — nomes
  #  totalmente reescritos, sem palavra em comum, mas 1↔1).
  #
  #  Condição B (mesmo slot reescrito): a legada compartilha ≥1 palavra de
  #  conteúdo com alguma canônica do nível (ex.: "Inspiração de Combate" ×
  #  "Inspiração em Combate"). Cobre níveis com vários slots onde a contagem
  #  não fecha 1:1.
  #
  # Se nenhuma condição se aplica, a feature fica visível e é reportada como
  # D1/D2 (limpeza de dados) — não adivinhamos.
  def resolve_legacy_canonical_pairs!(items)
    grouped = items.group_by { |it| [it[:level].to_i, it[:source]] }
    grouped.each do |(_level, source), group|
      next unless source == 'SubKlass'
      visible = group.select { |it| it[:show] != false }
      next if visible.size < 2

      canonical = visible.select { |it| it[:canonical] }
      # Candidatas legadas: não-canônicas, não-placeholder (placeholders já
      # foram tratados), e mais antigas que a menor canônica do nível.
      next if canonical.empty?
      min_canon_id = canonical.map { |c| c[:id].to_i }.min
      legacy = visible.reject { |it| it[:canonical] || placeholder?(it) }
                      .select { |it| it[:id].to_i < min_canon_id }
      next if legacy.empty?

      clean_one_to_one = (legacy.size == canonical.size)
      canon_tokens = canonical.map { |c| content_tokens(c[:name]) }

      legacy.each do |leg|
        if clean_one_to_one
          leg[:show] = false
          next
        end
        leg_tokens = content_tokens(leg[:name])
        next if leg_tokens.empty?
        leg[:show] = false if canon_tokens.any? { |ct| (ct & leg_tokens).any? }
      end
    end
  end

  # Palavras de conteúdo (≥4 letras, sem stopwords) normalizadas — usadas para
  # detectar que duas features são o MESMO slot apesar de nomes diferentes.
  def content_tokens(name)
    normalize_name(name)
      .split(/[^\p{L}]+/)
      .reject { |t| t.length < 4 || STOPWORDS.include?(t) }
      .to_set
  end

  # Mapa { [level, nome_normalizado] => true } com os nomes de feature que o
  # `levels_json` (YAML curado) declara para a subclasse — a fonte de verdade
  # do nome canônico. Subclasses sem levels_json válido → mapa vazio (nenhuma
  # canônica detectada; dedup cai no critério de maior id).
  def canonical_names_by_level(sub_klass)
    raw = sub_klass.levels_json
    return {} if raw.blank?

    rows = JSON.parse(raw) rescue nil
    return {} unless rows.is_a?(Array)

    out = {}
    rows.each do |row|
      next unless row.is_a?(Hash)
      lvl = (row['level'] || row[:level]).to_i
      next if lvl <= 0
      Array(row['features'] || row[:features]).each do |feat|
        name = feat.is_a?(Hash) ? (feat['name'] || feat[:name]) : feat
        next if name.to_s.strip.empty?
        out[[lvl, normalize_name(name)]] = true
      end
    end
    out
  rescue StandardError
    {}
  end

  def placeholder?(item)
    return true if PLACEHOLDER_API_PATTERNS.any? { |re| item[:api_index].to_s.match?(re) }
    PLACEHOLDER_NAME_PATTERNS.any? { |re| item[:name].to_s.match?(re) }
  end

  # transliterate + downcase + colapsa espaços. Mantém o nome comparável
  # entre acentuação/caixa/espaços diferentes sem fundir nomes distintos.
  def normalize_name(value)
    value.to_s
         .unicode_normalize(:nfd)
         .gsub(/\p{Mn}/, '')
         .downcase
         .gsub(/\s+/, ' ')
         .strip
  end

  def sync_characters_features!
    @sheet.sheet_klasses.includes(:klass).each do |sk|
      FeatureGrantService.call(sheet: @sheet, klass: sk.klass, from_level: 0, to_level: sk.level)
    end
  end
end
