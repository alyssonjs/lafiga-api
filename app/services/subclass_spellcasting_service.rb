# frozen_string_literal: true

class SubclassSpellcastingService
  # Service para gerenciar spellcasting de subclasses customizadas

  def initialize(sub_klass, level)
    @sub_klass = sub_klass
    @level = level
    @klass = @sub_klass.klass
  end

  def call
    return nil unless has_spellcasting?

    subclass_rule = SubclassRules.find(@klass.api_index, @sub_klass.api_index)
    return nil unless subclass_rule&.dig(:spellcasting)

    spellcasting_data = subclass_rule[:spellcasting]
    
    {
      ability: spellcasting_data[:ability],
      spell_list: spellcasting_data[:spell_list],
      cantrips_known: calculate_cantrips_known(spellcasting_data),
      spells_known: calculate_spells_known(spellcasting_data),
      spell_slots: calculate_spell_slots(spellcasting_data),
      spell_save_dc: calculate_spell_save_dc(spellcasting_data),
      spell_attack_bonus: calculate_spell_attack_bonus(spellcasting_data)
    }
  end

  private

  def has_spellcasting?
    @sub_klass.has_spellcasting? || subclass_has_spellcasting_rule?
  end

  def subclass_has_spellcasting_rule?
    subclass_rule = SubclassRules.find(@klass.api_index, @sub_klass.api_index)
    subclass_rule&.dig(:spellcasting).present?
  end

  def calculate_cantrips_known(spellcasting_data)
    cantrips_table = spellcasting_data[:cantrips_known] || {}
    
    # Encontrar o valor mais próximo para o nível atual
    cantrips_table.keys.sort.reverse.each do |level_threshold|
      return cantrips_table[level_threshold] if @level >= level_threshold
    end
    
    # Valor padrão se não encontrar
    0
  end

  def calculate_spells_known(spellcasting_data)
    spells_table = spellcasting_data[:spells_known] || {}
    
    # Encontrar o valor mais próximo para o nível atual
    spells_table.keys.sort.reverse.each do |level_threshold|
      return spells_table[level_threshold] if @level >= level_threshold
    end
    
    # Valor padrão se não encontrar
    0
  end

  def calculate_spell_slots(spellcasting_data)
    slots_table = spellcasting_data[:spell_slots] || {}
    
    # Encontrar o valor mais próximo para o nível atual
    slots_table.keys.sort.reverse.each do |level_threshold|
      return slots_table[level_threshold] if @level >= level_threshold
    end
    
    # Valor padrão se não encontrar
    []
  end

  def calculate_spell_save_dc(spellcasting_data)
    ability = spellcasting_data[:ability]&.downcase
    return 8 unless ability

    ability_score = case ability
                   when 'str' then @sub_klass.sheet_klasses.first&.sheet&.str || 10
                   when 'dex' then @sub_klass.sheet_klasses.first&.sheet&.dex || 10
                   when 'con' then @sub_klass.sheet_klasses.first&.sheet&.con || 10
                   when 'int' then @sub_klass.sheet_klasses.first&.sheet&.int || 10
                   when 'wis' then @sub_klass.sheet_klasses.first&.sheet&.wis || 10
                   when 'cha' then @sub_klass.sheet_klasses.first&.sheet&.cha || 10
                   else 10
                   end

    ability_modifier = (ability_score - 10) / 2
    8 + ability_modifier + calculate_proficiency_bonus
  end

  def calculate_spell_attack_bonus(spellcasting_data)
    ability = spellcasting_data[:ability]&.downcase
    return 0 unless ability

    ability_score = case ability
                   when 'str' then @sub_klass.sheet_klasses.first&.sheet&.str || 10
                   when 'dex' then @sub_klass.sheet_klasses.first&.sheet&.dex || 10
                   when 'con' then @sub_klass.sheet_klasses.first&.sheet&.con || 10
                   when 'int' then @sub_klass.sheet_klasses.first&.sheet&.int || 10
                   when 'wis' then @sub_klass.sheet_klasses.first&.sheet&.wis || 10
                   when 'cha' then @sub_klass.sheet_klasses.first&.sheet&.cha || 10
                   else 10
                   end

    ability_modifier = (ability_score - 10) / 2
    ability_modifier + calculate_proficiency_bonus
  end

  def calculate_proficiency_bonus
    # Bônus de proficiência baseado no nível total do personagem
    # Assumindo que é o nível da classe principal
    case @level
    when 1..4 then 2
    when 5..8 then 3
    when 9..12 then 4
    when 13..16 then 5
    when 17..20 then 6
    else 2
    end
  end
end
