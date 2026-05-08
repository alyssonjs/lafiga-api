# frozen_string_literal: true

# Calcula PV máximo a partir de `metadata.class_choices.per_level` + colunas da ficha,
# alinhado a `CharacterProvisioningService` e ao wizard (dado+CON por nível + racial).
module SheetHpFromProgression
  module_function

  def level_one_floor(sheet, klass)
    hit_die = klass.hit_die.to_i.nonzero? || 8
    con_mod = CharacterRules.modifier(sheet.con)
    [1, hit_die + con_mod].max
  end

  def hp_gain_for_level_row(h, hit_die, con_mod)
    if h.is_a?(Hash)
      dr = h['dieResult'] || h[:dieResult] || h['die_result'] || h[:die_result]
      if dr.present?
        [dr.to_i + con_mod, 1].max
      elsif (h['total'] || h[:total]).present?
        [(h['total'] || h[:total]).to_i, 1].max
      else
        [(hit_die / 2.0).ceil + con_mod, 1].max
      end
    else
      [(hit_die / 2.0).ceil + con_mod, 1].max
    end
  end

  def expected_max(sheet, klass, character_level, per_level)
    hit_die = klass.hit_die.to_i.nonzero? || 8
    con_mod = CharacterRules.modifier(sheet.con)
    row1 = per_level['1'] || per_level[1] || {}
    h1 = row1.is_a?(Hash) ? (row1['hp'] || row1[:hp]) : nil
    total = if h1.is_a?(Hash)
              hp_gain_for_level_row(h1, hit_die, con_mod)
            else
              [1, hit_die + con_mod].max
            end

    if character_level.to_i > 1
      (2..character_level.to_i).each do |lv|
        row = per_level[lv.to_s] || per_level[lv] || {}
        h = row['hp'] || row[:hp]
        total += hp_gain_for_level_row(h, hit_die, con_mod)
      end
    end

    # Racial HP bonus (ex.: Robustez Anã do Hill Dwarf, +1 PV/nível). Antes do
    # fix, o `return total if character_level <= 1` saía ANTES desta linha,
    # então o `init_hp` em CPS aplicava o +1 corretamente, mas
    # `finalize_sheet_hp_after_provision!` chamava aqui e SOBRESCREVIA o
    # hp_max sem o racial — Hill Dwarf nv 1 ficava com 12 em vez de 13.
    # Cobertura: race_creation_dwarf_bdd_spec.rb (Hill).
    racial = RacialHpBonus.per_level_for_sheet(sheet) * [character_level.to_i, 1].max
    total += racial if racial.positive?

    # Feat HP bonus (ex.: PHB Tough/Robusto +2 PV/nível). Antes deste fix,
    # PCs com Robusto aplicado retroativamente (após criação ou via Variant
    # Human) ficavam com sheet.hp_max sem o +N×nível, gerando divergência
    # entre o resumo (front recalculava) e a ficha (lia sheet.hp_max direto).
    # Cobertura: spec/services/feat_hp_bonus_spec.rb.
    feat_hp = FeatHpBonus.total_for_sheet(sheet, character_level.to_i)
    total += feat_hp if feat_hp.positive?

    total
  end
end
