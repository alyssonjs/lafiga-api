# frozen_string_literal: true

# Helpers puros usados pela rake `spells:import_xlsx` para reconciliar
# magias entre `spells.yml` e `spelldatabase.parsed.json`. Extraidos do
# corpo da rake para serem unitariamente testaveis sem precisar carregar
# Rake::Application ou tocar I/O.
module SpellsImportHelpers
  module_function

  # Lowercase + strip diacritics; usado em todas as comparacoes de nome,
  # school, casting_time, etc.
  def fold(s)
    s.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.strip
  end

  def slugify_pt(name)
    fold(name).gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')
  end

  def generate_pt_api_index(name, used)
    base = "pt-#{slugify_pt(name)}"
    return base unless used.include?(base)
    i = 2
    loop do
      candidate = "#{base}-#{i}"
      return candidate unless used.include?(candidate)
      i += 1
    end
  end

  # Mutates `row` in place with values from xlsx-parsed `sp`. Preserves
  # api_index. Replaces desc / higher_level / components / material /
  # casting_time / range / duration. Keeps existing keys when xlsx field is
  # empty (defensivo).
  def merge_into_existing(row, sp)
    row['name'] = sp['name'] if sp['name'].to_s != ''
    row['level'] = sp['level'].to_i if sp['level']
    row['school'] = sp['school'] if sp['school'].to_s != ''
    row['range'] = sp['range'] if sp['range'].to_s != ''
    row['components'] = sp['components'] if sp['components'].is_a?(Array) && !sp['components'].empty?
    row['material'] = sp['material']
    row['ritual'] = sp['ritual'] ? true : false
    row['duration'] = sp['duration'] if sp['duration'].to_s != ''
    row['concentration'] = sp['concentration'] ? true : false
    row['casting_time'] = sp['casting_time'] if sp['casting_time'].to_s != ''
    row['desc'] = Array(sp['desc']).reject { |x| x.to_s.strip.empty? }
    row['higher_level'] = Array(sp['higher_level']).reject { |x| x.to_s.strip.empty? }
    row
  end

  def build_new_row(sp, api_index)
    {
      'api_index'    => api_index,
      'name'         => sp['name'],
      'level'        => sp['level'].to_i,
      'school'       => sp['school'],
      'range'        => sp['range'],
      'components'   => Array(sp['components']),
      'material'     => sp['material'],
      'ritual'       => sp['ritual'] ? true : false,
      'duration'     => sp['duration'],
      'concentration' => sp['concentration'] ? true : false,
      'casting_time' => sp['casting_time'],
      'desc'         => Array(sp['desc']).reject { |x| x.to_s.strip.empty? },
      'higher_level' => Array(sp['higher_level']).reject { |x| x.to_s.strip.empty? },
    }
  end

  def same_payload?(a, b)
    keys = %w[name level school range components material ritual duration concentration casting_time desc higher_level]
    keys.all? { |k| a[k] == b[k] }
  end

  # Detecta se dois nomes sao "quase iguais" — tolera:
  # 1. capitalizacao + diacritico (via fold)
  # 2. singular/plural PT-BR (via stem: "guardioes" -> "guardiao")
  # 3. typos curtos (Levenshtein <= max(2, 15% do menor))
  # NAO casa nomes genuinamente diferentes como "Moldar Agua" vs
  # "Moldar Terra" (stems diferentes, distancia 4+).
  def near_duplicate_names?(a, b)
    na = fold(a).gsub(/\s+/, ' ').strip
    nb = fold(b).gsub(/\s+/, ' ').strip
    return false if na.empty? || nb.empty?
    return true if na == nb
    return true if stem_pt(na) == stem_pt(nb)
    threshold = [2, ([na.length, nb.length].min * 0.15).ceil].max
    levenshtein(na, nb) <= threshold
  end

  # Implementacao classica O(m*n) de Levenshtein. Para nomes <= 80 chars
  # o custo e desprezivel (~0.1ms cada par).
  def levenshtein(s, t)
    return t.length if s.empty?
    return s.length if t.empty?
    m = s.length
    n = t.length
    prev = (0..n).to_a
    curr = Array.new(n + 1, 0)
    (1..m).each do |i|
      curr[0] = i
      (1..n).each do |j|
        cost = s[i - 1] == t[j - 1] ? 0 : 1
        curr[j] = [
          curr[j - 1] + 1,
          prev[j] + 1,
          prev[j - 1] + cost,
        ].min
      end
      prev, curr = curr, prev
    end
    prev[n]
  end

  # Stemmer minimal PT-BR: remove sufixos plurais comuns palavra-a-palavra.
  PLURAL_RULES = [
    [/oes$/, 'ao'],
    [/aes$/, 'ao'],
    [/ais$/, 'al'],
    [/eis$/, 'el'],
    [/ois$/, 'ol'],
    [/uis$/, 'ul'],
    [/res$/, 'r'],
    [/zes$/, 'z'],
    [/ses$/, 's'],
    [/ns$/,  'm'],
  ].freeze

  def stem_pt(s)
    s.split(' ').map { |w| stem_word(w) }.join(' ')
  end

  def stem_word(w)
    return w if w.length < 4
    PLURAL_RULES.each do |re, repl|
      return w.sub(re, repl) if w =~ re
    end
    w.sub(/s$/, '')
  end

  # Decide qual de duas magias com mesma signature deve ser MANTIDA no YML.
  # Regra: api_index NAO `pt-*` (canonico SRD/oficial) vence. Em empate, `a`.
  def pick_canonical(a, b)
    a_pt = a['api_index'].to_s.start_with?('pt-')
    b_pt = b['api_index'].to_s.start_with?('pt-')
    return [b, a] if a_pt && !b_pt
    [a, b]
  end

  def signature_for_yml(row)
    sig_tuple(row['level'], row['school'], row['casting_time'], row['range'], Array(row['components']))
  end

  def signature_for_xlsx(sp)
    sig_tuple(sp['level'], sp['school'], sp['casting_time'], sp['range'], Array(sp['components']))
  end

  def sig_tuple(level, school, casting_time, range, components)
    [
      level.to_i,
      fold(school),
      fold(casting_time).gsub(/\s+/, ' '),
      fold(range).gsub(/\s+/, ' '),
      components.map(&:to_s).map { |c| fold(c) }.sort,
    ]
  end
end
