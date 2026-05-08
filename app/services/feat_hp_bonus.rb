# frozen_string_literal: true

# Soma o bônus de PV por nível concedido por feats (paralelo ao
# `RacialHpBonus` que cobre traços raciais como Robustez Anã).
#
# Caso PHB Tough (Robusto): +2 PV por nível, retroativo + por level up.
# Antes deste helper, o backend somava `RacialHpBonus` mas ignorava o feat
# Robusto em `LevelUpService` e em `SheetHpFromProgression.expected_max`.
# Resultado: PC com Robusto via assignment retroativo (não no LevelUpWizard)
# tinha sheet.hp_max sem +12 (= base do Bárbaro nv6) e o resumo no front
# (que recalcula) divergia da ficha completa (que lê sheet.hp_max direto).
module FeatHpBonus
  module_function

  # Lê metadata['feats'][n]['special_rules']['dice_modifiers']['hit_points_bonus'] e soma
  # `bonus_per_level` × char_level. Aceita também a forma legacy
  # `dice.hit_points_per_level.bonus_per_level`.
  #
  # @return [Integer] bônus total (>= 0)
  def per_level_for_sheet(sheet)
    return 0 unless sheet&.metadata.is_a?(Hash)

    feats = Array(sheet.metadata['feats'])
    per_level = feats.sum do |entry|
      next 0 unless entry.is_a?(Hash)
      sr = entry['special_rules'] || entry[:special_rules] || {}
      bonus_per_level_from(sr)
    end
    per_level.to_i
  end

  # Calcula o total RETROATIVO (per_level × char_level). Usado em
  # `expected_max` para validar drift e em `FeatAssignmentService` para
  # decidir se precisa atualizar sheet.hp_max após assignment retroativo.
  def total_for_sheet(sheet, character_level)
    per_level = per_level_for_sheet(sheet)
    return 0 if per_level <= 0
    per_level * [character_level.to_i, 0].max
  end

  def bonus_per_level_from(special_rules)
    sr = special_rules.is_a?(Hash) ? special_rules : {}

    hp = sr.dig('dice_modifiers', 'hit_points_bonus') ||
         sr.dig(:dice_modifiers, :hit_points_bonus) ||
         sr.dig('dice', 'hit_points_per_level') ||
         sr.dig(:dice, :hit_points_per_level)

    return 0 unless hp.is_a?(Hash)

    params = hp['parameters'] || hp[:parameters] || hp
    (params['bonus_per_level'] || params[:bonus_per_level] || params['bonus'] || params[:bonus]).to_i
  end
end
