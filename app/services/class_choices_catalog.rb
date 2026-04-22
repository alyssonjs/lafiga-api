# Loader de catálogos canônicos de escolhas de classe.
#
# Lê arquivos YAML em api/config/class_choices/, valida o schema, e expõe
# em memória. Usado por ClassRules.dictionaries e por LevelUpGuardService
# (subset validation).
#
# Schema completo: api/config/class_choices/SCHEMA.md
#
# Uso:
#
#   ClassChoicesCatalog.load(:metamagic)
#   # => [{ slug: 'mm-careful', name_pt: 'Magia Cuidadosa', ... }, ...]
#
#   ClassChoicesCatalog.resolve(:metamagic, 'Suturar Magia')
#   # => { slug: 'mm-careful', name_pt: 'Magia Cuidadosa', ... }  (matched via alias)
#
#   ClassChoicesCatalog.slugs(:metamagic)
#   # => ['mm-careful', 'mm-distant', ...]
class ClassChoicesCatalog
  CONFIG_DIR = Rails.root.join('config', 'class_choices').to_s.freeze

  # Lista exaustiva de chaves permitidas em prereqs (validation).
  # `subclass` foi adicionado por Kit 1.snacks: gating canônico por subclasse
  # (ex.: petisco do Mestre da Fritura só elegível se a subclasse for essa).
  ALLOWED_PREREQ_KEYS = %w[level pact spell class blast ability_min subclass].freeze

  # Campos top-level opcionais (string livre, apenas tipo é validado).
  # Usados por catálogos com metadata extra de gameplay/UI:
  #   - school    : escola arcana (Transmutation, Abjuration, Evocation, ...)
  #   - range     : alcance do efeito (Touch, Self, "9 m radius", ...)
  #   - duration  : duração ("Instantaneous", "1 minute", "10 minutes", ...)
  #   - higher_level : escalonamento opcional (texto livre)
  OPTIONAL_STRING_FIELDS = %w[school range duration higher_level].freeze

  # Custos válidos para metamágicas (e similares).
  # 'spell_level' = custo igual ao nível da magia (Twinned Spell).
  # 'variable'    = custo variável definido por mechanical_summary
  #                 (ex.: Shape the Flowing River usa 0 ou 1 Ki).
  VALID_COST_STRINGS = %w[spell_level variable].freeze

  class SchemaError < StandardError; end

  class << self
    # Carrega e cacheia o catálogo. Em produção/dev, mantém em memória depois
    # do primeiro load. Em test/desenvolvimento de YAML, chame `reset!` ou
    # restart o container.
    def load(catalog_name)
      cache[catalog_name.to_sym] ||= load_and_validate(catalog_name)
    end

    # Lookup por slug, name_pt, name_en ou alias. Retorna o hash completo ou nil.
    def resolve(catalog_name, identifier)
      return nil if identifier.blank?
      key = identifier.to_s.strip
      entries = load(catalog_name)
      entries.find do |entry|
        entry[:slug] == key ||
          entry[:name_pt] == key ||
          entry[:name_en] == key ||
          Array(entry[:aliases]).include?(key)
      end
    end

    # Lista de slugs canônicos (para validação de subset rápida).
    def slugs(catalog_name)
      load(catalog_name).map { |e| e[:slug] }
    end

    # Lista de nomes PT (gravados em class_choices durante a transição —
    # frente ainda envia name_pt; depois de Kit 1.PoC.front migra pra slug).
    def canonical_names(catalog_name)
      load(catalog_name).map { |e| e[:name_pt] }
    end

    # Lista de identificadores aceitos pra validação (slug + name_pt + name_en + aliases).
    # Usado por LevelUpGuardService.resolve_subset_options para tolerância máxima
    # durante a transição (até backfill completar).
    def acceptable_identifiers(catalog_name)
      load(catalog_name).flat_map do |e|
        [e[:slug], e[:name_pt], e[:name_en], *Array(e[:aliases])].compact
      end.uniq
    end

    # Limpa cache (uso em testes / após edit de YAML).
    def reset!
      @cache = {}
    end

    private

    def cache
      @cache ||= {}
    end

    def load_and_validate(catalog_name)
      path = File.join(CONFIG_DIR, "#{catalog_name}.yml")
      raise SchemaError, "Catálogo #{catalog_name} não encontrado em #{path}" unless File.exist?(path)

      raw = YAML.safe_load_file(path, permitted_classes: [], aliases: false) || []
      raise SchemaError, "Catálogo #{catalog_name} deve ser uma lista no topo (got: #{raw.class})" unless raw.is_a?(Array)

      seen_slugs = {}
      seen_names = {}
      seen_aliases = {}

      entries = raw.each_with_index.map do |entry, idx|
        validate_entry!(entry, catalog_name, idx, seen_slugs, seen_names, seen_aliases)
        normalize_entry(entry)
      end

      entries.freeze
    end

    def validate_entry!(entry, catalog_name, idx, seen_slugs, seen_names, seen_aliases)
      raise SchemaError, "[#{catalog_name}#%d] entry deve ser hash" % idx unless entry.is_a?(Hash)
      slug = entry['slug']
      raise SchemaError, "[#{catalog_name}#%d] slug obrigatório" % idx if slug.blank?
      raise SchemaError, "[#{catalog_name}##{idx}] slug '#{slug}' inválido (deve ser kebab-case: ^[a-z0-9-]+$)" unless slug =~ /\A[a-z0-9-]+\z/
      raise SchemaError, "[#{catalog_name}] slug duplicado: '#{slug}' (entries ##{seen_slugs[slug]} e ##{idx})" if seen_slugs.key?(slug)
      seen_slugs[slug] = idx

      name_pt = entry['name_pt']
      raise SchemaError, "[#{catalog_name}##{idx} #{slug}] name_pt obrigatório" if name_pt.blank?
      raise SchemaError, "[#{catalog_name}] name_pt duplicado: '#{name_pt}' (entries ##{seen_names[name_pt]} e ##{idx})" if seen_names.key?(name_pt)
      seen_names[name_pt] = idx

      name_en = entry['name_en']
      raise SchemaError, "[#{catalog_name}##{idx} #{slug}] name_en obrigatório" if name_en.blank?

      desc = entry['description']
      raise SchemaError, "[#{catalog_name}##{idx} #{slug}] description obrigatório" if desc.blank?
      raise SchemaError, "[#{catalog_name}##{idx} #{slug}] description muito curta (#{desc.length} < 30 chars)" if desc.length < 30

      summary = entry['mechanical_summary']
      raise SchemaError, "[#{catalog_name}##{idx} #{slug}] mechanical_summary obrigatório" if summary.blank?
      raise SchemaError, "[#{catalog_name}##{idx} #{slug}] mechanical_summary muito longo (#{summary.length} > 100 chars)" if summary.length > 100

      cost = entry['cost']
      if cost.present?
        valid = cost.is_a?(Integer) && cost >= 0
        valid ||= cost.is_a?(String) && VALID_COST_STRINGS.include?(cost)
        raise SchemaError, "[#{catalog_name}##{idx} #{slug}] cost inválido: #{cost.inspect}" unless valid
      end

      classes = entry['classes']
      if classes.present?
        raise SchemaError, "[#{catalog_name}##{idx} #{slug}] classes deve ser array" unless classes.is_a?(Array)
        classes.each do |c|
          raise SchemaError, "[#{catalog_name}##{idx} #{slug}] classes deve conter strings" unless c.is_a?(String)
        end
      end

      prereqs = entry['prereqs']
      if prereqs.present?
        raise SchemaError, "[#{catalog_name}##{idx} #{slug}] prereqs deve ser hash" unless prereqs.is_a?(Hash)
        unknown_keys = prereqs.keys - ALLOWED_PREREQ_KEYS
        if unknown_keys.any?
          raise SchemaError, "[#{catalog_name}##{idx} #{slug}] prereqs contém chave(s) inválida(s): #{unknown_keys.inspect}. Permitidas: #{ALLOWED_PREREQ_KEYS.inspect}"
        end
      end

      OPTIONAL_STRING_FIELDS.each do |field|
        val = entry[field]
        next if val.nil?
        unless val.is_a?(String)
          raise SchemaError, "[#{catalog_name}##{idx} #{slug}] #{field} deve ser string (got: #{val.class})"
        end
      end

      aliases = entry['aliases']
      if aliases.present?
        raise SchemaError, "[#{catalog_name}##{idx} #{slug}] aliases deve ser array" unless aliases.is_a?(Array)
        aliases.each do |a|
          raise SchemaError, "[#{catalog_name}##{idx} #{slug}] alias deve ser string" unless a.is_a?(String)
          if seen_aliases.key?(a)
            raise SchemaError, "[#{catalog_name}] alias duplicado: '#{a}' (entries ##{seen_aliases[a]} e ##{idx})"
          end
          seen_aliases[a] = idx
        end
      end
    end

    def normalize_entry(entry)
      base = {
        slug: entry['slug'],
        name_pt: entry['name_pt'],
        name_en: entry['name_en'],
        aliases: Array(entry['aliases']),
        description: entry['description'].strip,
        mechanical_summary: entry['mechanical_summary'].strip,
        cost: entry['cost'],
        classes: Array(entry['classes']),
        prereqs: entry['prereqs'] || {}
      }
      OPTIONAL_STRING_FIELDS.each do |field|
        val = entry[field]
        base[field.to_sym] = val if val.is_a?(String) && !val.empty?
      end
      base.compact.freeze
    end
  end
end
