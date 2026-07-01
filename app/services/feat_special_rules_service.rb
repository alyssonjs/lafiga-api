# frozen_string_literal: true

class FeatSpecialRulesService
  # Service para aplicar regras especiais de feats que vão além dos bônus básicos
  
  def initialize(sheet, feat_id, choices = {})
    @sheet = sheet
    @feat_id = feat_id
    @choices = choices
  end

  def apply_special_rules
    # Try to get from database first, then fallback to FeatRules.
    # IMPORTANTE: a coluna `feats.special_rules` e `text`, entao chega como
    # String JSON (apos o fix em lib/tasks/import_feats.rake) ou Ruby
    # Hash#inspect (legacy). `FeatRules.parse_jsonish` cura ambos os casos
    # e devolve HashWithIndifferentAccess. Antes deste fix, indexar a
    # String por simbolo (`special_rules[:movement_modifiers]`) jogava
    # `TypeError: no implicit conversion of Symbol into Integer`, e o
    # rescue silencioso de toplevel em FeatAssignmentService transformava
    # isso em "metadata['feats'] vazio + ficha sem bonus" (mesmo sintoma
    # do bug Adimael/Observador). Cobertura: spec/services/level_up_service_feats_spec.rb.
    feat_record = Feat.find_by(api_index: @feat_id)
    if feat_record&.special_rules.present?
      special_rules = FeatRules.parse_jsonish(feat_record.special_rules)
      # Se nao for hash apos parse (string corrompida ou vazia), cai pro fallback.
      special_rules = nil unless special_rules.is_a?(Hash)
    end
    if special_rules.nil?
      feat_rule = FeatRules.find(@feat_id)
      return {} unless feat_rule&.dig(:special_rules)
      special_rules = feat_rule[:special_rules]
    end

    applied_rules = {}

    # Aplicar regras de movimento
    movement_rules = special_rules[:movement_modifiers] || special_rules['movement_modifiers']
    if movement_rules
      applied_rules[:movement] = apply_movement_modifiers(movement_rules)
    end

    # Aplicar regras de combate
    combat_rules = special_rules[:combat_modifiers] || special_rules['combat_modifiers']
    if combat_rules
      applied_rules[:combat] = apply_combat_modifiers(combat_rules)
    end

    # Aplicar regras de defesa
    defense_rules = special_rules[:defense_modifiers] || special_rules['defense_modifiers']
    if defense_rules
      applied_rules[:defense] = apply_defense_modifiers(defense_rules)
    end

    # Aplicar regras de dados
    dice_rules = special_rules[:dice_modifiers] || special_rules['dice_modifiers']
    if dice_rules
      applied_rules[:dice] = apply_dice_modifiers(dice_rules)
    end

    # Aplicar regras de magia
    magic_rules = special_rules[:magic_modifiers] || special_rules['magic_modifiers']
    if magic_rules
      applied_rules[:magic] = apply_magic_modifiers(magic_rules)
    end

    # Aplicar regras de perícias
    skill_rules = special_rules[:skill_modifiers] || special_rules['skill_modifiers']
    if skill_rules
      applied_rules[:skills] = apply_skill_modifiers(skill_rules)
    end

    # Aplicar regras de equipamento
    equipment_rules = special_rules[:equipment_modifiers] || special_rules['equipment_modifiers']
    if equipment_rules
      applied_rules[:equipment] = apply_equipment_modifiers(equipment_rules)
    end

    # F2 — Preservação total: qualquer família FORA da allowlist acima
    # (healing_modifiers, temporary_hp_modifiers, social_modifiers,
    # exploration_modifiers, utility_modifiers, unarmed_modifiers) e qualquer
    # chave top-level que não seja `*_modifiers` (maneuvers/superiority_die do
    # Adepto Marcial) era silenciosamente descartada e `special_rules` persistia
    # `{}`. Agora preservamos o sub-hash cru sob a chave normalizada para que
    # build_resources / FeatProducer / front possam ler. Não sobrescreve nenhuma
    # família já processada acima.
    special_rules.each do |fam_key, fam_val|
      key_s = fam_key.to_s
      next if KNOWN_FAMILY_KEYS.include?(key_s)
      next if fam_val.nil?

      norm = key_s.sub(/_modifiers\z/, '').to_sym
      next if applied_rules.key?(norm)

      applied_rules[norm] = fam_val.respond_to?(:deep_stringify_keys) ? fam_val.deep_stringify_keys : fam_val
    end

    applied_rules
  end

  private

  # Famílias com handler dedicado (transformam a estrutura). Tudo o que estiver
  # fora desta lista é preservado cru pela passada de "preservação total" acima.
  KNOWN_FAMILY_KEYS = %w[
    movement_modifiers combat_modifiers defense_modifiers
    dice_modifiers magic_modifiers skill_modifiers equipment_modifiers
  ].freeze

  # Valor de fallback para um `modifier_type` sem `when` explícito: preserva os
  # `parameters` crus (Hash/Array/String) ou `true` quando não houver. Evita que
  # chaves novas (Alerta initiative_bonus, Adepto Elemental elemental_focus,
  # Conjurador de Ritual ritual_book, Maestria Média dex_cap, etc.) caiam no vazio.
  def passthrough_value(config)
    return config unless config.is_a?(Hash)
    params = config['parameters'] || config[:parameters]
    params.nil? ? true : params
  end

  def apply_movement_modifiers(modifiers)
    result = {}
    
    modifiers.each do |modifier_type, config|
      case modifier_type.to_s
      when 'speed_bonus'
        params = config['parameters'] || config[:parameters]
        result[:speed_bonus] = params['bonus'] || params[:bonus] || params['value'] || params[:value]
      when 'difficult_terrain_immunity'
        params = config['parameters'] || config[:parameters]
        result[:ignore_difficult_terrain] = params['condition'] || params[:condition] || params['trigger'] || params[:trigger]
      when 'stealth_conditions'
        result[:stealth_in_light_obscurement] = true
      end
    end

    result
  end

  def apply_combat_modifiers(modifiers)
    result = {}
    
    modifiers.each do |modifier_type, config|
      params = config['parameters'] || config[:parameters] || {}
      
      case modifier_type.to_s
      when 'cover_immunity', 'cover_ignoring'
        # Handle both array and hash parameters
        if params.is_a?(Array)
          result[:ignore_cover_types] = params
        else
          result[:ignore_cover_types] = params['types'] || params[:types] || params
        end
      when 'range_advantage', 'long_range_no_disadvantage'
        result[:no_long_range_disadvantage] = params['weapon_type'] || params[:weapon_type] || params['weapon_category'] || params[:weapon_category]
      when 'power_attack'
        result[:power_attack_option] = {
          attack_penalty: params['attack_penalty'] || params[:attack_penalty],
          damage_bonus: params['damage_bonus'] || params[:damage_bonus],
          weapon_type: params['weapon_type'] || params[:weapon_type] || params.dig('weapon_filter', 'category') || params.dig(:weapon_filter, :category)
        }
      when 'spell_range_double'
        result[:double_spell_range] = params['spell_type'] || params[:spell_type] || params['spell_attack'] || params[:spell_attack]
      when 'bonus_action_attack', 'bonus_action_offhand', 'bonus_action_butt_attack'
        result[:bonus_action_attack] = params
      when 'opportunity_attack_enhancement', 'reduce_speed_to_zero'
        result[:oa_reduce_movement_to_zero] = true
      when 'opportunity_attack_immunity', 'no_oa_after_attack'
        result[:no_oa_after_attack] = params['condition'] || params[:condition] || params['trigger'] || params[:trigger]
      when 'oa_on_enter_reach'
        result[:oa_on_enter_reach] = params['weapon_list'] || params[:weapon_list]
      when 'provoke_oa_ignores_disengage'
        result[:oa_even_if_disengage] = true
      when 'protect_ally_reaction'
        result[:melee_reaction_against_attacker] = params
      when 'bonus_action_shove'
        result[:bonus_action_shove] = params
      when 'shield_bonus_to_dex_save'
        result[:shield_bonus_to_dex_save] = params
      when 'advantage_vs_smaller'
        result[:advantage_melee_vs_smaller_than_mount] = true
      when 'redirect_attack_to_self'
        result[:redirect_attack_from_mount] = params
      when 'mount_evasion_like'
        result[:dex_save_half_to_zero_for_mount] = params
      when 'advantage_vs_grappled'
        result[:advantage_on_attack_vs_grappled_target] = true
      when 'pin_as_action'
        result[:attempt_pin_grappled_target] = params
      when 'missed_ranged_attack_does_not_reveal'
        result[:stay_hidden_on_missed_ranged_attack] = true
      else
        # F2 — Alerta (initiative_bonus/surprise_immunity/ignore_hidden_attacker_advantage),
        # Matador de Conjuradores (reaction_attack_on_cast/...), etc.: preserva cru.
        result[modifier_type.to_sym] = params.presence || true
      end
    end

    result
  end

  # Helper: extrai parametros aceitando tanto chaves simbolo (FeatRules.find ->
  # Ruby hash) quanto strings (Feat#special_rules vindo de JSONB).
  def params_for(config)
    return {} unless config.is_a?(Hash)
    raw = config['parameters'] || config[:parameters] || {}
    raw.is_a?(Hash) ? raw : {}
  end

  # Como `params_for`, mas NÃO descarta `parameters` que não sejam Hash. Usado
  # nos handlers cujo valor é exposto cru (skill_advantage com Array de perícias,
  # reaction_ac_bonus com String 'proficiency_bonus', damage_resistance com
  # Array de condições). Devolve nil quando não houver `parameters` (F3).
  def raw_params(config)
    return config unless config.is_a?(Hash)
    config['parameters'] || config[:parameters]
  end

  # Helper: leitura agnostica de simbolo/string.
  def pv(params, *keys)
    keys.each do |k|
      return params[k.to_s] if params.key?(k.to_s)
      return params[k.to_sym] if params.key?(k.to_sym)
    end
    nil
  end

  def apply_defense_modifiers(modifiers)
    result = {}

    modifiers.each do |modifier_type, config|
      # F3 — `parameters` pode ser Hash (Maestria Pesada {reduce:3,...}), Array
      # (Explorador de Cavernas ['armadilhas']) ou String (Duelista Defensivo
      # 'proficiency_bonus'). `params_for` descartava Array/String → {}. Aqui
      # preservamos o valor cru.
      params = raw_params(config)
      case modifier_type.to_s
      when 'reaction_ac_bonus'
        result[:reaction_ac_bonus] = params
      when 'shield_master_reaction'
        result[:shield_master_reaction] = true
      when 'damage_resistance'
        result[:damage_resistance] = params
      else
        # F2 — Maestria em Armadura Média (medium_armor_dex_cap / stealth_*), etc.
        result[modifier_type.to_sym] = params.nil? ? true : params
      end
    end

    result
  end

  def apply_dice_modifiers(modifiers)
    result = {}

    modifiers.each do |modifier_type, config|
      params = params_for(config)
      case modifier_type.to_s
      when 'luck_points'
        result[:luck_points] = {
          points: pv(params, :points),
          recovery: pv(params, :recovery),
          uses: pv(params, :uses)
        }
      when 'damage_reroll'
        result[:damage_reroll] = {
          frequency: pv(params, :frequency),
          attack_type: pv(params, :attack_type)
        }
      when 'hit_points_bonus'
        result[:hit_points_per_level] = {
          bonus_per_level: pv(params, :bonus_per_level).to_i,
          retroactive: pv(params, :retroactive)
        }
      else
        # F2 — Durável (hit_dice_minimum_heal), etc.
        result[modifier_type.to_sym] = params.presence || true
      end
    end

    result
  end

  def apply_magic_modifiers(modifiers)
    result = {}

    modifiers.each do |modifier_type, config|
      params = params_for(config)
      case modifier_type.to_s
      when 'somatic_components_with_hands_full'
        result[:somatic_with_hands_full] = pv(params, :equipment)
      when 'spell_as_opportunity_attack'
        result[:spell_as_oa] = {
          spell_action: pv(params, :spell_action),
          target_restriction: pv(params, :target_restriction)
        }
      when 'learn_cantrip'
        result[:learn_cantrip] = {
          type: pv(params, :type),
          class_choice: pv(params, :class_choice)
        }
      else
        # F2 — Adepto Elemental (elemental_focus), Conjurador de Ritual
        # (ritual_book/ritual_copying/ritual_casting): preserva cru. F7 consome
        # learn_cantrip/ritual_book em apply_feat_spells.
        result[modifier_type.to_sym] = raw_params(config).nil? ? true : raw_params(config)
      end
    end

    result
  end

  def apply_skill_modifiers(modifiers)
    result = {}

    modifiers.each do |modifier_type, config|
      # F3 — skill_advantage vem como Array de perícias (Ator: ['Atuação',
      # 'Enganação']); preservar cru em vez de zerar via params_for.
      params = raw_params(config)
      case modifier_type.to_s
      when 'skill_advantage'
        result[:skill_advantage] = params
      when 'saving_throw_advantage'
        result[:saving_throw_advantage] = params
      when 'lip_reading'
        result[:lip_reading] = params
      else
        result[modifier_type.to_sym] = params.nil? ? true : params
      end
    end

    result
  end

  def apply_equipment_modifiers(modifiers)
    result = {}

    modifiers.each do |modifier_type, config|
      params = params_for(config)
      case modifier_type.to_s
      when 'weapon_property_ignore'
        result[:ignore_weapon_property] = {
          property: pv(params, :property),
          weapon_type: pv(params, :weapon_type)
        }
      when 'armor_class_bonus'
        result[:equipment_ac_bonus] = {
          condition: pv(params, :condition),
          bonus: pv(params, :bonus).to_i
        }
      when 'weapon_restriction_removal'
        result[:remove_weapon_restriction] = params
      when 'dual_wield_draw'
        result[:dual_wield_draw] = params
      else
        result[modifier_type.to_sym] = params.presence || true
      end
    end

    result
  end

  # Método para calcular bônus de PV retroativos
  def self.calculate_retroactive_hp_bonus(sheet, feat_id)
    feat_rule = FeatRules.find(feat_id)
    return 0 unless feat_rule&.dig(:special_rules, :dice_modifiers, :hit_points_bonus)

    bonus_per_level = feat_rule[:special_rules][:dice_modifiers][:hit_points_bonus][:parameters][:bonus_per_level]
    current_level = sheet.sheet_klasses.sum(:level)
    
    current_level * bonus_per_level
  end

  # Método para verificar se uma regra especial está ativa
  def self.has_special_rule?(sheet, feat_id, rule_type, rule_name)
    metadata = sheet.metadata || {}
    feats = metadata['feats'] || []
    
    feat_data = feats.find { |f| f['feat_id'] == feat_id }
    return false unless feat_data&.dig('special_rules', rule_type, rule_name)

    true
  end

  # Método para obter valor de uma regra especial
  def self.get_special_rule_value(sheet, feat_id, rule_type, rule_name)
    metadata = sheet.metadata || {}
    feats = metadata['feats'] || []
    
    feat_data = feats.find { |f| f['feat_id'] == feat_id }
    return nil unless feat_data

    feat_data.dig('special_rules', rule_type, rule_name)
  end
end
