# frozen_string_literal: true

# Service para aplicar magias inatas de raças/sub-raças aos personagens
# Exemplos:
# - Drow: Luz Dançante (1), Fogo das Fadas (3), Escuridão (5)
# - Tiefling: Thaumaturgy (1), Hellish Rebuke (3), Darkness (5)
# - High Elf: 1 cantrip de Wizard à escolha
#
# Uso:
#   RacialSpellsService.call(sheet: sheet, race_rule: race_rule, character_level: 5)
class RacialSpellsService
  prepend SimpleCommand

  def initialize(sheet:, race_rule:, character_level: nil)
    @sheet = sheet
    @race_rule = race_rule
    @character_level = character_level || CharacterRules.total_level(@sheet)
  end

  def call
    # Bug "Drow → Tiefling guardava magias antigas":
    # antes deste reset, `find_or_initialize_by` so adicionava as magias da
    # nova raca, sem nunca remover as da raca anterior. Resultado:
    # SheetKnownSpell acumulava `source: 'race'` de cada raca passada (ex.:
    # Globos de Luz do Drow continuavam mesmo depois de virar Tiefling).
    # Cobertura: spec/services/racial_spells_service_spec.rb (resetagem).
    sk_ids = @sheet.sheet_klasses.pluck(:id)
    if sk_ids.any?
      removed = SheetKnownSpell.where(sheet_klass_id: sk_ids, source: 'race').delete_all
      removed_prep = SheetPreparedSpell.where(sheet_id: @sheet.id, source: 'race').delete_all
      if removed.positive? || removed_prep.positive?
        Rails.logger.info "RacialSpellsService: cleared #{removed} known + #{removed_prep} prepared racial spells for sheet #{@sheet.id}"
      end
    end

    innate_spells = collect_innate_spells
    return @sheet if innate_spells.empty?

    primary_sk = @sheet.sheet_klasses.order(level: :desc).first

    unless primary_sk
      Rails.logger.warn "RacialSpellsService: No sheet_klass found for sheet #{@sheet.id}"
      return @sheet
    end

    applied_count = 0

    innate_spells.each do |spell_entry|
      spell = find_spell(spell_entry[:name])
      
      unless spell
        Rails.logger.warn "RacialSpellsService: Spell not found: #{spell_entry[:name]}"
        next
      end

      # Criar ou atualizar SheetKnownSpell
      sheet_known_spell = SheetKnownSpell.find_or_initialize_by(
        sheet_klass: primary_sk,
        spell: spell
      )

      # Sync de progressão (`sync_sheet_known_spells_from_spell_selections!`) pode gravar a magia
      # inata como `class` antes deste serviço — promover para `race` para chips (RAÇA) e summary.
      if sheet_known_spell.persisted? && sheet_known_spell.source != 'race'
        unless sheet_known_spell.source == 'class'
          Rails.logger.info "RacialSpellsService: Spell #{spell.name} already known from #{sheet_known_spell.source}"
          next
        end
      end

      sheet_known_spell.assign_attributes(
        source: 'race',
        gained_at_class_level: spell_entry[:unlocked_at_level],
        uses_per_rest: spell_entry[:uses], # 'LR', 'SR', ou nil
        uses_remaining: calculate_initial_uses(spell_entry[:uses])
      )

      if sheet_known_spell.save
        applied_count += 1
        Rails.logger.info "RacialSpellsService: Applied #{spell.name} (level #{spell.level}) to #{@sheet.character.name}"
      else
        Rails.logger.warn "RacialSpellsService: Failed to save #{spell.name}: #{sheet_known_spell.errors.full_messages.join(', ')}"
      end
    end

    Rails.logger.info "RacialSpellsService: Applied #{applied_count} racial spells to character level #{@character_level}"
    @sheet
  end

  private

  def collect_innate_spells
    results = []

    # D2/R3b — Truque(s) RACIAL(is) À ESCOLHA (ex.: Alto Elfo → 1 truque de
    # Mago). O front coleta em `race_choices.chosenCantrip` /
    # `race_choices.traitOptions.<trait_key>`, mas NENHUM serviço do backend lia
    # isso: o truque era perdido na ficha persistida. Aqui resolvemos a escolha
    # do jogador para os trait_defs de ESCOLHA (`options.choose`) e criamos o
    # SheetKnownSpell(source:'race').
    collect_chosen_cantrips(results)

    # Legado: grupos `{ level:, spells: [...] }` (ex.: specs, alguns YAML antigos)
    process_innate_spells_array(@race_rule[:innate_spells], results)

    # RaceRules.apply: `extract_innate_spells_from_traits` devolve entradas flat
    # `{ name:, unlocked_at_level:, ability:, uses: }` com `spell` do trait como api_index/slug.
    Array(@race_rule[:innate_spells]).each do |entry|
      next unless entry.is_a?(Hash)

      legacy_list = entry[:spells] || entry['spells']
      next if legacy_list.present?

      key = entry[:name] || entry['name']
      next if key.blank?

      unlocked = (entry[:unlocked_at_level] || entry['unlocked_at_level'] || 1).to_i
      next if @character_level < unlocked

      results << {
        name: key,
        ability: (entry[:ability] || entry['ability'] || 'CHA').to_s,
        uses: entry[:uses] || entry['uses'],
        unlocked_at_level: unlocked
      }
    end

    results
  end

  # D2/R3b — Resolve truques raciais à escolha do jogador.
  #
  # Trait de ESCOLHA = trait ref com `options.choose` (e `spell_list`/`filters`)
  # — ex.: high_elf_cantrip. A escolha persistida vive em
  # `metadata.race_choices.traitOptions[<trait_key>]` (preferencial, preciso) ou
  # `metadata.race_choices.chosenCantrip` (fallback quando há 1 só escolha).
  # Cada valor pode ser slug/api_index, nome ou Hash {id/name}.
  def collect_chosen_cantrips(results)
    choices = (@sheet.metadata || {})['race_choices'] || (@sheet.metadata || {})[:race_choices] || {}
    choices = choices.deep_stringify_keys if choices.is_a?(Hash)
    return unless choices.is_a?(Hash)

    trait_opts = choices['traitOptions'] || {}
    trait_opts = trait_opts.is_a?(Hash) ? trait_opts.deep_stringify_keys : {}
    fallback   = normalize_choice_value(choices['chosenCantrip'])

    Array(@race_rule[:traits]).each do |ref|
      next unless ref.is_a?(Hash)

      opts = ref[:options] || ref['options']
      next unless opts.is_a?(Hash) && (opts[:choose] || opts['choose']).to_i.positive?

      key = (ref[:key] || ref['key']).to_s
      picked = normalize_choice_value(trait_opts[key]) || fallback
      next if picked.blank?

      ability = (opts[:ability] || opts['ability'] || 'INT').to_s
      results << {
        name: picked,
        ability: ability,
        uses: nil,                # truque = à vontade
        unlocked_at_level: 1
      }
    end
  end

  # Extrai o identificador (slug/nome) de um valor de escolha que pode vir como
  # String, Hash {id/name} ou Array (usa o 1º).
  def normalize_choice_value(raw)
    case raw
    when String then raw.strip.presence
    when Array  then normalize_choice_value(raw.first)
    when Hash
      h = raw.deep_stringify_keys
      (h['id'] || h['name'] || h['api_index']).to_s.strip.presence
    end
  end

  def process_innate_spells_array(innate_spells_array, results)
    Array(innate_spells_array).each do |entry|
      req_level = (entry[:level] || entry['level'] || 1).to_i
      next if @character_level < req_level
      
      spells_list = entry[:spells] || entry['spells']
      ability = entry[:ability] || entry['ability'] || 'CHA'
      # Default LR only when the rule omits `uses`; explicit nil = unlimited (cantrips)
      uses = if entry.key?(:uses)
               entry[:uses]
             elsif entry.key?('uses')
               entry['uses']
             else
               'LR'
             end
      
      Array(spells_list).each do |spell_name|
        results << {
          name: spell_name,
          ability: ability,
          uses: uses,
          unlocked_at_level: req_level
        }
      end
    end
  end

  def find_spell(spell_name)
    SpellResolver.new.resolve(spell_name)
  end

  def calculate_initial_uses(uses_per_rest)
    case uses_per_rest&.to_s&.upcase
    when 'LR', 'LONG_REST'
      1 # Magias raciais geralmente são 1x por descanso longo
    when 'SR', 'SHORT_REST'
      1 # Se fosse short rest, também 1x
    else
      0 # Cantrips não têm usos limitados
    end
  end
end

