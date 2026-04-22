# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────
# MonsterEngineSyncService
#
# Espelha MagicItemEngineSyncService: faz upsert em Monster a partir de YAML
# (string ou Hash) ou JSON Hash, no formato:
#
#   { "monsters" => { "<slug>" => { ...MonsterEntry attrs... }, ... } }
#
# Tambem aceita um array (`{ "monsters" => [ {id:..., name:...}, ... ] }`)
# para compat com o dump direto do front (`MONSTER_DATABASE.ts -> JSON`).
# ─────────────────────────────────────────────────────────────────────────
class MonsterEngineSyncService
  Result = Struct.new(:upserted, :created, :updated, :skipped, :errors, :details, keyword_init: true)

  def self.call(payload, dry_run: false, default_source: 'srd')
    new(payload, dry_run: dry_run, default_source: default_source).call
  end

  def initialize(payload, dry_run: false, default_source: 'srd')
    @payload = payload
    @dry_run = dry_run
    @default_source = default_source
  end

  def call
    rows    = extract_rows(@payload)
    details = []
    created = updated = skipped = 0
    errors  = []

    rows.each do |slug, row|
      begin
        attrs = build_attrs(slug, row)
        m = Monster.find_or_initialize_by(slug: slug)
        was_new = m.new_record?
        m.assign_attributes(attrs)

        if @dry_run
          status = was_new ? 'would_create' : (m.changed? ? 'would_update' : 'no_change')
          details << { slug: slug, status: status }
        elsif m.changed? || was_new
          m.save!
          if was_new
            created += 1
            details << { slug: slug, status: 'created' }
          else
            updated += 1
            details << { slug: slug, status: 'updated' }
          end
        else
          skipped += 1
          details << { slug: slug, status: 'no_change' }
        end
      rescue => e
        errors << { slug: slug, message: "#{e.class}: #{e.message}" }
        details << { slug: slug, status: 'error', error: e.message }
      end
    end

    Result.new(
      upserted: created + updated,
      created:  created,
      updated:  updated,
      skipped:  skipped,
      errors:   errors,
      details:  details
    )
  end

  private

  def build_attrs(slug, row)
    payload = row.is_a?(Hash) ? row.dup : {}
    payload.delete('id') # slug eh a fonte da verdade
    {
      name:        row['name'] || slug.to_s.tr('-', ' ').titleize,
      name_en:     row['nameEN'] || row['name_en'],
      payload:     payload,
      source:      row['source'] || @default_source,
    }
  end

  # Aceita YAML string, Hash {monsters: {slug => {...}}}, ou Array de
  # entradas com `id`/`slug`.
  def extract_rows(payload)
    case payload
    when String
      parsed = YAML.safe_load(payload, permitted_classes: [Symbol]) || {}
      data   = parsed['monsters'] || parsed[:monsters] || parsed
      normalize_rows(data)
    when Hash
      data = payload['monsters'] || payload[:monsters] || payload
      normalize_rows(data)
    when Array
      normalize_rows(payload)
    else
      raise ArgumentError, "Unsupported payload type: #{payload.class}"
    end
  end

  def normalize_rows(data)
    case data
    when Hash
      data.transform_keys(&:to_s).map do |slug, row|
        [slug, deep_stringify(row)]
      end
    when Array
      data.map do |row|
        h    = deep_stringify(row)
        slug = h['slug'].presence || h['id'].presence || raise(ArgumentError, "Row missing slug/id: #{h['name']}")
        [slug.to_s, h]
      end
    else
      raise ArgumentError, 'monsters payload must be a Hash or Array'
    end
  end

  def deep_stringify(obj)
    case obj
    when Hash  then obj.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify(v) }
    when Array then obj.map { |x| deep_stringify(x) }
    else obj
    end
  end
end
