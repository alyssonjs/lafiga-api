# frozen_string_literal: true

# Phase 2.2 — Fidelidade dos números
#
# Compara campo a campo o que a XLSX da campanha dizia que o personagem TINHA
# vs o que o `CharacterProvisioningService` produziu. As checagens são
# divididas em camadas:
#
#   STRICT  → falham o spec se divergirem (passados em wizard.race.attributes
#             explicitamente, então têm que bater 100%).
#               • abilities (str/dex/con/int/wis/cha)
#               • current_level
#               • proficiency_bonus (CharacterRules)
#
#   WINDOW  → falham se o valor cair fora de uma janela razoável. HP do
#             builder usa média do hit die — em geral abaixo do HP "real"
#             jogado nos dados pelo player na XLSX.
#               • hp_max ∈ [hp_min_possivel, hp_max_possivel]
#
#   REPORT  → não falham; só registram a divergência num hash global
#             para inspeção depois (e mostram no log se houver).
#               • hp_max  (XLSX vs sistema)
#               • spell_save_dc (XLSX vs CharacterSheetSummaryService)
#               • spell_attack  (XLSX vs CharacterSheetSummaryService)
#               • speed_m       (XLSX vs sheet)
#
# O resultado consolidado fica em
#   File.join(Rails.root, 'tmp', 'phase22_fidelity_report.json')
# para inspeção fora do RSpec.
module ImportedSheetsFidelityReport
  module_function

  REPORT_PATH = -> { Rails.root.join('tmp', 'phase22_fidelity_report.json') }

  ABILITY_KEYS = %w[str dex con int wis cha].freeze

  def reset!
    @entries = {}
  end

  def entries
    @entries ||= {}
  end

  def add(tab, payload)
    entries[tab] = payload
  end

  def flush!
    FileUtils.mkdir_p(File.dirname(REPORT_PATH.call))
    File.write(REPORT_PATH.call, JSON.pretty_generate(entries))
  end

  # ---------- comparações --------------------------------------------------

  # Tier 1 — STRICT
  def expected_abilities(sheet_xlsx)
    abilities = sheet_xlsx['abilities'] || {}
    {
      'str' => score(abilities, 'strength'),
      'dex' => score(abilities, 'dexterity'),
      'con' => score(abilities, 'constitution'),
      'int' => score(abilities, 'intelligence'),
      'wis' => score(abilities, 'wisdom'),
      'cha' => score(abilities, 'charisma')
    }
  end

  def actual_abilities(sheet_record)
    {
      'str' => sheet_record.str.to_i, 'dex' => sheet_record.dex.to_i,
      'con' => sheet_record.con.to_i, 'int' => sheet_record.int.to_i,
      'wis' => sheet_record.wis.to_i, 'cha' => sheet_record.cha.to_i
    }
  end

  def proficiency_bonus_for(level)
    ((level.to_i - 1) / 4) + 2
  end

  # Tier 2 — WINDOW (HP)
  # Para o builder atual:
  #   L1     -> hd + con_mod
  #   L2..N  -> ceil(hd/2) + con_mod  (mas cap em min 1)
  # XLSX pode trazer valores maiores (rolagens reais) ou um HP_max enriquecido
  # por feats (Toughness +2/level), Hill Dwarf (+1/level), Draconic Resilience
  # (sorcerer +1/level), etc. A janela aceita do extremo "todos 1" ao
  # extremo "todos max + +2/level (Toughness) + +1/level (race)".
  def hp_window(klass_record, level, con_mod)
    hd = klass_record.hit_die.to_i.nonzero? || 8
    base_max_per_extra_level = hd + con_mod
    base_min_per_extra_level = 1 + con_mod

    extras = level - 1
    {
      min: [hd + con_mod + base_min_per_extra_level * extras, level].max,
      max: hd + con_mod + base_max_per_extra_level * extras + (3 * level)
    }
  end

  # ---------- helpers internos ---------------------------------------------

  def score(abilities, key)
    raw = abilities.dig(key, 'score') || abilities[key]
    val = raw.is_a?(Numeric) ? raw.to_i : raw.to_i
    val.between?(1, 30) ? val : 10
  end
end
