# frozen_string_literal: true

# Lógica (testável) do importer de `spells.combat_data`. O rake
# `spells:import_combat_data` é um wrapper fino sobre `import!`.
#
# Fontes:
#   - db/seeds/spell_combat_data.json   (auto-derivado da Open5e SRD)
#   - config/spell_combat_overrides.yml (curadoria manual)
#
# Merge: RASO no topo (override[api] sobre seed[api]); chaves com valor nil
# são podadas (permite o override "apagar" um campo do seed).
module SpellCombatDataImporter
  SEED_PATH = -> { Rails.root.join('db', 'seeds', 'spell_combat_data.json') }
  OVERRIDES_PATH = -> { Rails.root.join('config', 'spell_combat_overrides.yml') }

  module_function

  def load_seed
    path = SEED_PATH.call
    File.exist?(path) ? JSON.parse(File.read(path)) : {}
  end

  def load_overrides
    path = OVERRIDES_PATH.call
    return {} unless File.exist?(path)

    data = YAML.safe_load(File.read(path), permitted_classes: [], aliases: true)
    data.is_a?(Hash) ? data : {}
  end

  # Combina seed + overrides (merge raso, poda nils). Função PURA.
  def merged(seed, overrides)
    (seed.keys + overrides.keys).uniq.each_with_object({}) do |api, acc|
      data = (seed[api] || {}).merge(overrides[api] || {}).reject { |_, v| v.nil? }
      acc[api] = data unless data.empty?
    end
  end

  # Aplica no banco. Retorna um Hash de contadores + slugs sem magia.
  # `dry_run` não escreve; `reset` zera combat_data de todas as magias antes.
  def import!(dry_run: false, reset: false, logger: nil)
    entries = merged(load_seed, load_overrides)
    log = ->(m) { logger&.call(m) }

    if reset && !dry_run
      Spell.where.not(combat_data: {}).update_all(combat_data: {})
      log.call('[combat_data] RESET: combat_data zerado em todas as magias.')
    end

    counts = Hash.new(0)
    missing = []
    entries.each do |api, data|
      spell = Spell.find_by(api_index: api)
      if spell.nil?
        missing << api
        counts[:missing] += 1
        next
      end
      if spell.combat_data == data
        counts[:unchanged] += 1
        next
      end
      counts[:updated] += 1
      spell.update!(combat_data: data) unless dry_run
    end

    log.call("[combat_data] #{dry_run ? '(DRY_RUN) ' : ''}entradas: #{entries.size} | " \
             "atualizadas: #{counts[:updated]} | inalteradas: #{counts[:unchanged]} | " \
             "sem magia no banco: #{counts[:missing]}")
    log.call("[combat_data] slugs sem magia: #{missing.sort.join(', ')}") if missing.any?

    { entries: entries.size, updated: counts[:updated], unchanged: counts[:unchanged],
      missing: missing.sort }
  end
end
