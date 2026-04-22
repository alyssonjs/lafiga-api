# Resolvedor centralizado de Spell por id/name/api_index/translations/aliases.
#
# Por que existe:
#   Antes desse service havia DUAS implementacoes paralelas com a MESMA cadeia
#   de fallbacks dentro de `KnownSpellsAggregator` (lambdas `resolver` e
#   `resolve_spell`), e `LevelUpService#persist_known_spells!` simplesmente
#   pulava entradas cujo `id` nao fosse numerico — sem warn, sem fallback. Um
#   typo no excel original (ex.: "Toque arrepiane" em vez de "Toque
#   Arrepiante") fazia a magia ser silenciosamente descartada do `SheetKnownSpell`
#   e ficar como string crua dentro de `metadata.class_choices.per_level[N]`,
#   exibida na ficha sem icone/descricao.
#
  # Cadeia de resolucao (na ordem):
#   1. Spell#id numerico
#   2. Spell#name (case-sensitive)
#   3. Spell#name LOWER(name) (case-insensitive)
#   4. Spell#api_index a partir do nome transliterado/sluggificado
#   5. Spell#api_index a partir do dnd_translations.yml (PT-BR -> EN slug)
#   6. Spell#api_index a partir do spell_aliases.yml (typos conhecidos)
#   7. Indice em memoria sobre Spell.name (transliterate+downcase) — captura
#      acento divergente ("Risada Historica" vs "Risada Histórica") e
#      pequenas variacoes que nao bateriam em LOWER puro.
#
# Uso:
#   resolver = SpellResolver.new
#   sp = resolver.resolve("Toque arrepiane")        # => Spell(api_index=chill-touch)
#   sp = resolver.resolve({ "id" => "Toque arrepiane", "name" => "Toque arrepiane" })
#   sp = resolver.resolve(123)                       # por id
#
# Cache:
#   `SpellResolver.new` mantem cache local entre chamadas — instancie UMA vez
#   por request/loop e reaproveite. Cada chave unica vira 1 query (no maximo).
#   `KnownSpellsAggregator` e `LevelUpService` instanciam um por chamada,
#   reaproveitando entre todos os spells daquela operacao.
class SpellResolver
  TRANSLATIONS_PATH = 'config/dnd_translations.yml'
  ALIASES_PATH      = 'config/spell_aliases.yml'

  def initialize
    @cache_by_id        = {}
    @cache_by_name_low  = {}
    @cache_by_api_index = {}
  end

  # `input` pode ser:
  #   - Integer (id)
  #   - String (name)
  #   - Hash com `id` e/ou `name` (keys string ou symbol)
  # Retorna `Spell` ou `nil`.
  def resolve(input)
    sid, sname = extract(input)

    if sid.is_a?(Integer) || (sid.is_a?(String) && sid =~ /\A\d+\z/)
      sp = lookup_by_id(sid.to_i)
      return sp if sp
    end

    return nil if sname.blank?

    sp = lookup_by_name_exact(sname)
    return sp if sp

    sp = lookup_by_name_lower(sname)
    return sp if sp

    sp = lookup_by_slug(slugify(sname))
    return sp if sp

    tr_slug = translation_map[sname.to_s.downcase]
    if tr_slug.present?
      sp = lookup_by_api_index(tr_slug)
      return sp if sp
    end

    # Aliases sao matched de forma agnostica a acento (transliterate de ambos
    # os lados) para que typos historicos como "cão fiel de mordenkai" e
    # "cao fiel de mordenkai" caiam na mesma chave do yml.
    al_key = ActiveSupport::Inflector.transliterate(sname.to_s).downcase.strip.gsub(/\s+/, ' ')
    al_slug = aliases_map[al_key]
    if al_slug.present?
      sp = lookup_by_api_index(al_slug)
      return sp if sp
    end

    # Ultimo recurso: indice em memoria construido com transliterate(downcase(name))
    # — pega divergencia de acentos sem precisar de extensao Postgres (pg_trgm).
    norm = normalize_for_index(sname)
    sp_id = self.class.transliterated_index[norm]
    return lookup_by_id(sp_id) if sp_id

    nil
  end

  # Helper para LevelUpService/persist_known_spells!: dada uma entrada do
  # metadata (Hash/String/Integer), devolve um Hash canonicalizado
  # `{ id:, name:, level: }` quando resolver, ou `nil` quando nao resolver.
  # Nao escreve em DB — quem chama decide.
  def normalize(input)
    sp = resolve(input)
    return nil unless sp
    { id: sp.id, name: sp.name, level: sp.level.to_i, api_index: sp.api_index }
  end

  private

  def extract(input)
    case input
    when Integer
      [input, nil]
    when String
      input =~ /\A\d+\z/ ? [input.to_i, nil] : [nil, input]
    when Hash
      sid_raw = input['id'] || input[:id]
      sname   = input['name'] || input[:name]
      sid = sid_raw.is_a?(Integer) ? sid_raw : (sid_raw.to_s =~ /\A\d+\z/ ? sid_raw.to_i : nil)
      # sid_raw textual (ex.: "Toque arrepiane") nao serve como id numerico;
      # cai pra resolucao por nome. Mas se name estiver vazio, usa o sid_raw
      # textual como nome de ultimo recurso.
      sname = sid_raw if sname.blank? && sid_raw.is_a?(String) && sid.nil?
      [sid, sname]
    else
      [nil, nil]
    end
  end

  def lookup_by_id(sid)
    return @cache_by_id[sid] if @cache_by_id.key?(sid)
    @cache_by_id[sid] = Spell.find_by(id: sid)
  end

  def lookup_by_name_exact(sname)
    key = "exact:#{sname}"
    return @cache_by_name_low[key] if @cache_by_name_low.key?(key)
    @cache_by_name_low[key] = Spell.find_by(name: sname)
  end

  def lookup_by_name_lower(sname)
    key = "lower:#{sname.to_s.downcase}"
    return @cache_by_name_low[key] if @cache_by_name_low.key?(key)
    @cache_by_name_low[key] = Spell.where('LOWER(name) = ?', sname.to_s.downcase).first
  end

  def lookup_by_api_index(slug)
    return @cache_by_api_index[slug] if @cache_by_api_index.key?(slug)
    @cache_by_api_index[slug] = Spell.find_by(api_index: slug)
  end

  def lookup_by_slug(slug)
    return nil if slug.blank?
    lookup_by_api_index(slug)
  end

  def slugify(s)
    ActiveSupport::Inflector
      .transliterate(s.to_s)
      .downcase
      .gsub(/[^a-z0-9]+/, '-')
      .gsub(/^-+|-+$/, '')
  end

  # Normalizacao usada SO no indice em memoria (passo 7). Mantem espacos
  # (em vez de virar slug com `-`) pra evitar colisao acidental com
  # `lookup_by_api_index` e ja remove acentos.
  def normalize_for_index(s)
    ActiveSupport::Inflector
      .transliterate(s.to_s)
      .downcase
      .strip
      .gsub(/\s+/, ' ')
  end

  # Cache de classe (lifetime do processo). Recarrega so se o arquivo mudar
  # (mtime). Em prod, esses arquivos sao imutaveis durante o processo => 1 leitura.
  def translation_map
    self.class.translation_map
  end

  def aliases_map
    self.class.aliases_map
  end

  class << self
    def translation_map
      load_yaml_map(TRANSLATIONS_PATH, root_key: 'spells', invert_for: :pt_to_slug)
    end

    def aliases_map
      load_yaml_map(ALIASES_PATH, root_key: nil, invert_for: :alias_to_slug)
    end

    def reset_caches!
      @yaml_cache = {}
      @transliterated_index = nil
      @transliterated_index_built_at = nil
    end

    # Indice em memoria { normalized_name => spell_id } construido lazy.
    # Reconstroi a cada 10min (cobre seeds em dev sem custo absurdo).
    def transliterated_index
      now = Time.current
      if @transliterated_index.nil? ||
         @transliterated_index_built_at.nil? ||
         (now - @transliterated_index_built_at) > 600
        @transliterated_index = {}
        Spell.pluck(:id, :name).each do |sid, name|
          key = ActiveSupport::Inflector.transliterate(name.to_s).downcase.strip.gsub(/\s+/, ' ')
          # Em colisao, primeiro vencedor (Spell.name eh unique no DB normalmente).
          @transliterated_index[key] ||= sid
        end
        @transliterated_index_built_at = now
      end
      @transliterated_index
    end

    private

    def load_yaml_map(rel_path, root_key:, invert_for:)
      @yaml_cache ||= {}
      path = Rails.root.join(rel_path)
      return {} unless File.exist?(path)

      mtime = File.mtime(path).to_i
      cached = @yaml_cache[rel_path]
      return cached[:map] if cached && cached[:mtime] == mtime

      data = YAML.safe_load(File.read(path), permitted_classes: [Symbol], aliases: false) || {}
      data = data[root_key] || {} if root_key

      map = case invert_for
            when :pt_to_slug
              data.each_with_object({}) { |(slug, pt), h| h[pt.to_s.downcase] = slug.to_s }
            when :alias_to_slug
              # Normaliza chave do alias do mesmo jeito que o lookup vai
              # transliterar o input — evita confusao com acentos no yml.
              data.each_with_object({}) do |(alias_name, slug), h|
                key = ActiveSupport::Inflector.transliterate(alias_name.to_s).downcase.strip.gsub(/\s+/, ' ')
                h[key] = slug.to_s
              end
            else
              data
            end

      @yaml_cache[rel_path] = { mtime: mtime, map: map }
      map
    rescue => e
      Rails.logger.warn "SpellResolver: falha lendo #{rel_path}: #{e.message}" if defined?(Rails)
      {}
    end
  end
end
