# frozen_string_literal: true

require 'yaml'

# Bônus de PV máximo concedido por features de SUBCLASSE (paralelo a
# `RacialHpBonus` e `FeatHpBonus`).
#
# Caso houserule Cozinheiro › Sargento Alimentar › "Nunca Satisfeito" (Nv 3):
# PV máximo +3 imediato + 1 por nível subsequente nesta classe. As chaves vivem
# em `config/subclass_overrides.yml` sob a feature:
#   rules: { max_hp_bonus_immediate: 3, max_hp_bonus_per_level: 1 }
#
# Antes deste serviço, o YAML DECLARAVA as chaves mas nada as consumia — o PV
# nunca era aplicado (nem no backend, nem no front, que só exibia um badge).
# Genérico: qualquer subclasse com essas chaves passa a somar ao hp_max.
module SubclassHpBonus
  module_function

  def overrides
    @overrides ||= begin
      path = Rails.root.join('config', 'subclass_overrides.yml')
      File.exist?(path) ? (YAML.load_file(path) || {}) : {}
    rescue StandardError
      {}
    end
  end

  # Localiza o bloco da subclasse (`{ 'choose_level' =>, 'levels' => [...] }`)
  # pelo api_index, procurando em todas as classes do YAML (api_index de
  # subclasse é único).
  def subclass_block(subclass_api)
    key = subclass_api.to_s
    return nil if key.blank?

    overrides.each_value do |klass_block|
      next unless klass_block.is_a?(Hash)
      block = klass_block[key]
      return block if block.is_a?(Hash)
    end
    nil
  end

  # Bônus total de PV concedido por uma subclasse dado o nível NESSA classe.
  # Soma, para cada feature com as chaves: immediate + per_level × (nível - feature_level).
  def bonus_for(subclass_api, class_level)
    block = subclass_block(subclass_api)
    return 0 unless block.is_a?(Hash)

    lvl = class_level.to_i
    total = 0
    Array(block['levels'] || block[:levels]).each do |level_row|
      next unless level_row.is_a?(Hash)
      feat_level = (level_row['level'] || level_row[:level]).to_i
      Array(level_row['features'] || level_row[:features]).each do |feature|
        next unless feature.is_a?(Hash)
        rules = feature['rules'] || feature[:rules]
        next unless rules.is_a?(Hash)
        immediate = (rules['max_hp_bonus_immediate'] || rules[:max_hp_bonus_immediate]).to_i
        per_level = (rules['max_hp_bonus_per_level'] || rules[:max_hp_bonus_per_level]).to_i
        next if immediate.zero? && per_level.zero?
        next if lvl < feat_level # ainda não adquiriu a feature

        total += immediate + per_level * [lvl - feat_level, 0].max
      end
    end
    total
  end

  # Delta do bônus ao ATINGIR `new_level` nessa classe (para o modelo
  # incremental do LevelUpService): `bonus_for(new_level) - bonus_for(new_level-1)`.
  # No nível de aquisição da feature devolve o imediato; nos seguintes, o per_level.
  def step_bonus_for_klass(sheet_klass, new_level)
    sub = sheet_klass&.sub_klass
    return 0 unless sub
    api = sub.api_index.presence || sub.name.to_s.parameterize(separator: '-')
    lv = new_level.to_i
    bonus_for(api, lv) - bonus_for(api, lv - 1)
  end

  # Soma o bônus de todas as subclasses da ficha, cada uma usando o nível da
  # SUA classe (`SheetKlass.level`). Não conta duas vezes em multiclasse.
  # @return [Integer] bônus total (>= 0)
  def total_for_sheet(sheet)
    return 0 unless sheet

    sheet.sheet_klasses.sum do |sk|
      sub = sk.sub_klass
      next 0 unless sub
      api = sub.api_index.presence || sub.name.to_s.parameterize(separator: '-')
      bonus_for(api, sk.level)
    end.to_i.clamp(0, 999)
  rescue StandardError => e
    Rails.logger.warn("SubclassHpBonus: falha para sheet ##{sheet&.id}: #{e.class}: #{e.message}")
    0
  end
end
