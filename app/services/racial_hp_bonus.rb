# frozen_string_literal: true

# Bônus de PV por nível vindos de traços raciais (trait_definitions em race_rules.yml),
# ex.: Anão da Colina (`dwarven_toughness` → grants.hp_per_level).
#
# O valor aplicado usa o nível total do personagem (soma SheetKlass.level), alinhado ao 5e.
module RacialHpBonus
  module_function

  # Soma grants.hp_per_level dos trait_definitions para os traços combinados da raça+sub-raça.
  def per_level_from_applied(applied_traits)
    return 0 unless applied_traits
    defs = RaceRules.trait_definitions
    total = 0
    Array(applied_traits).each do |tr|
      key = tr.is_a?(Hash) ? (tr[:key] || tr['key']) : tr
      next if key.blank?
      defn = defs[key.to_sym] || defs[key.to_s]
      next unless defn.is_a?(Hash)
      g = defn[:grants] || defn['grants']
      next unless g.is_a?(Hash)
      amt = g[:hp_per_level] || g['hp_per_level']
      total += amt.to_i
    end
    total.clamp(0, 99)
  end

  def per_level_for_sheet(sheet)
    return 0 unless sheet&.race_id
    race = sheet.race
    return 0 unless race
    rid = race.api_index.to_s.presence || race.name.to_s.parameterize(separator: '_')
    sub = sheet.sub_race
    sid = sub&.api_index&.presence || sub&.name&.to_s&.parameterize(separator: '_')
    rc = (sheet.metadata || {}).fetch('race_choices', {}) || {}
    extra_langs = Array(rc['chosenLanguages']).flatten.compact.map(&:to_s)
    applied = RaceRules.apply(race_id: rid, subrace_id: sid, choices: { extraLanguages: extra_langs })
    per_level_from_applied(applied[:traits])
  rescue StandardError => e
    Rails.logger.warn("RacialHpBonus: falha ao resolver traços para sheet ##{sheet&.id}: #{e.class}: #{e.message}")
    0
  end

  # Usado antes de existir Sheet persistido (provisionamento inicial).
  def per_level_from_race_records(race_obj, sub_race_obj, race_choices)
    return 0 unless race_obj
    rid = race_obj.api_index.to_s.presence || race_obj.name.to_s.parameterize(separator: '_')
    sid = sub_race_obj&.api_index&.presence || sub_race_obj&.name&.to_s&.parameterize(separator: '_')
    rc = race_choices.is_a?(Hash) ? race_choices.deep_stringify_keys : {}
    extra_langs = Array(rc['chosenLanguages']).flatten.compact.map(&:to_s)
    applied = RaceRules.apply(race_id: rid, subrace_id: sid, choices: { extraLanguages: extra_langs })
    per_level_from_applied(applied[:traits])
  rescue StandardError => e
    Rails.logger.warn("RacialHpBonus: falha no provisionamento inicial: #{e.class}: #{e.message}")
    0
  end
end
