# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────
# MagicItemEngineSyncService
#
# Extrai a lógica de "upsert" do rake task `magic_items:sync_engine` para
# um serviço reutilizável, que pode ser invocado por:
#   • o próprio rake task (mantendo compatibilidade);
#   • o endpoint admin `POST /api/v1/admin/magic_items/bulk_import` (UI).
#
# Entrada: uma Hash no formato do YAML já parseado, OU uma string YAML.
# Saída:   OpenStruct com contagens (upserted, skipped, errors) e a lista
#          detalhada de resultados por slug.
# ─────────────────────────────────────────────────────────────────────────
class MagicItemEngineSyncService
  Result = Struct.new(:upserted, :created, :updated, :skipped, :errors, :details, keyword_init: true)

  def self.call(payload, dry_run: false)
    new(payload, dry_run: dry_run).call
  end

  # Categoria canónica + flag `is_wondrous` a partir de uma linha YAML (também usado
  # em `magic_items:import` para a tabela `items`).
  #
  # @return [Array(String, Boolean)] [category, is_wondrous]
  def self.category_and_wondrous_for_yaml_row(row)
    raw_cat = row['category']&.to_s&.strip
    is_w = row['is_wondrous']
    is_w = ActiveModel::Type::Boolean.new.cast(is_w) unless is_w.nil?

    if MagicItemCategoryMigration.legacy_wondrous_value?(raw_cat)
      is_w = true if is_w.nil?
      new_cat, = MagicItemCategoryMigration.from_legacy_wondrous_item(row['sub_category'])
    else
      new_cat = MagicItemCatalog.normalize_category(raw_cat)
    end

    is_w = false if new_cat && %w[weapon ammunition armor shield ring wand rod staff potion scroll].include?(new_cat.to_s)
    is_w = false if is_w.nil?
    [new_cat, is_w]
  end

  # @param payload [String, Hash] YAML string ou Hash já parseada (com chave 'magic_items')
  # @param dry_run [Boolean] se true, não persiste alterações (apenas valida)
  def initialize(payload, dry_run: false)
    @payload = payload
    @dry_run = dry_run
  end

  def call
    data = extract_items_hash(@payload)
    details = []
    created = updated = skipped = 0
    errors = []

    data.each do |key, row|
      slug = key.to_s
      begin
        props = row['props'] || {}
        new_cat, is_w = self.class.category_and_wondrous_for_yaml_row(row)

        attrs = {
          name:                row['name'] || slug.tr('-', ' '),
          rarity:              row['rarity'],
          category:            new_cat,
          sub_category:        row['sub_category'],
          is_wondrous:         is_w,
          requires_attunement: !!row['requires_attunement'],
          attunement_note:     row['attunement_note'],
          weight_kg:           self.class.to_kg(row['weight']),
          value_gp:            row['value_gp'],
          source:              row['source'],
          description:         row['description'],
          tags:                Array(row['tags']),
          bonuses:             props['bonuses']    || {},
          properties:          props['properties'] || {},
          effects:             props['effects']    || [],
        }
        mi = MagicItem.find_or_initialize_by(slug: slug)
        was_new = mi.new_record?
        mi.assign_attributes(attrs)

        if @dry_run
          status = was_new ? 'would_create' : (mi.changed? ? 'would_update' : 'no_change')
          details << { slug: slug, status: status }
        elsif mi.changed? || was_new
          mi.save!
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

  # ────────────────────────────────────────────────────────────────────
  # Helpers
  # ────────────────────────────────────────────────────────────────────

  # Converte strings como "2.5 kg", "5 lb" ou números para quilos (Float).
  def self.to_kg(val)
    return nil if val.nil?
    return val.to_f if val.is_a?(Numeric)
    s = val.to_s
    if (m = s.match(/([0-9]+(?:\.[0-9]+)?)\s*kg/i))
      m[1].to_f
    elsif (m = s.match(/([0-9]+(?:\.[0-9]+)?)\s*lb/i))
      m[1].to_f * 0.45359237
    else
      s.to_f
    end
  end

  private

  # Aceita YAML string, Hash já carregada, ou Hash direto (mapeamento slug→attrs).
  def extract_items_hash(payload)
    case payload
    when String
      parsed = YAML.safe_load(payload) || {}
      parsed['magic_items'] || parsed
    when Hash
      payload['magic_items'] || payload[:magic_items] || payload
    else
      raise ArgumentError, "Unsupported payload type: #{payload.class}"
    end
  end
end
